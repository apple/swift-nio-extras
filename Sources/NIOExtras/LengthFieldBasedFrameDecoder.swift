//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import Foundation

extension FixedWidthInteger {
    @inlinable
    init<D>(bytes: D) where D: DataProtocol {
        var integer = Self()
        withUnsafeMutableBytes(of: &integer) { (pointer) in
            _ = bytes.copyBytes(to: pointer, count: Swift.min(bytes.count, MemoryLayout<Self>.size))
        }
        self = integer
    }
    @inlinable
    func toEndianness(endianness: Endianness) -> Self {
        switch endianness {
        case .little:
            return self.littleEndian
        case .big:
            return self.bigEndian
        }
    }
}


extension ByteBuffer {
    mutating func readInteger<Integer>(byteCount: Int, endianess: Endianness, type: Integer.Type = Integer.self) -> Integer? where Integer: FixedWidthInteger {
        precondition(byteCount <= MemoryLayout<Integer>.size, "requested byte count does not fit into requested integer type")
        return readBytes(length: byteCount).map { bytes -> Integer in
            let integer = Integer(bytes: bytes).toEndianness(endianness: endianess)
            let missingLeadingZerosBytes = MemoryLayout<Integer>.size - byteCount
            return integer >> (missingLeadingZerosBytes * UInt8.bitWidth)
        }
    }
}

///
/// A decoder that splits the received `ByteBuffer` by the number of bytes specified in a fixed length header
/// contained within the buffer.
/// For example, if you received the following four fragmented packets:
///     +---+----+------+----+
///     | A | BC | DEFG | HI |
///     +---+----+------+----+
///
/// Given that the specified header length is 1 byte,
/// where the first header specifies 3 bytes while the second header specifies 4 bytes,
/// a `LengthFieldBasedFrameDecoder` will decode them into the following packets:
///
///     +-----+------+
///     | BCD | FGHI |
///     +-----+------+
///
/// 'A' and 'E' will be the headers and will not be passed forward.
///
public final class LengthFieldBasedFrameDecoder: ByteToMessageDecoder {
    ///
    /// An enumeration to describe the length of a piece of data in bytes.
    ///
    public enum ByteLength {
        case one
        case two
        case three
        case four
        case eight
        
        var length: Int {
            switch self {
            case .one:
                return 1
            case .two:
                return 2
            case .three:
                return 3
            case .four:
                return 4
            case .eight:
                return 8
            }
        }
    }
    
    ///
    /// The decoder has two distinct sections of data to read.
    /// Each must be fully present before it is considered as read.
    /// During the time when it is not present the decoder must wait. `DecoderReadState` details that waiting state.
    ///
    private enum DecoderReadState {
        case waitingForHeader
        case waitingForFrame(length: Int)
    }

    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    
    public var cumulationBuffer: ByteBuffer?
    private var readState: DecoderReadState = .waitingForHeader
    
    private let lengthFieldLength: ByteLength
    private let lengthFieldEndianness: Endianness
    
    /// Create `LengthFieldBasedFrameDecoder` with a given frame length.
    ///
    /// - parameters:
    ///    - lengthFieldLength: The length of the field specifying the remaining length of the frame.
    ///    - lengthFieldEndianness: The endianness of the field specifying the remaining length of the frame.
    ///
    public init(lengthFieldLength: ByteLength, lengthFieldEndianness: Endianness = .big) {

        // The value contained in the length field must be able to be represented by an integer type on the platform.
        // ie. .eight == 64bit which would not fit into the Int type on a 32bit platform.
        precondition(lengthFieldLength.length <= Int.bitWidth/8)
            
        self.lengthFieldLength = lengthFieldLength
        self.lengthFieldEndianness = lengthFieldEndianness
    }
    
    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        
        if case .waitingForHeader = self.readState {
            try self.readNextLengthFieldToState(buffer: &buffer)
        }
        
        guard case .waitingForFrame(let frameLength) = self.readState else {
            return .needMoreData
        }
        
        guard let frameBuffer = try self.readNextFrame(buffer: &buffer, frameLength: frameLength) else {
            return .needMoreData
        }
        
        context.fireChannelRead(self.wrapInboundOut(frameBuffer))

        return .continue
    }
    
    public func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        // we'll just try to decode as much as we can as usually
        while case .continue = try self.decode(context: context, buffer: &buffer) {}
        if buffer.readableBytes > 0 {
            context.fireErrorCaught(NIOExtrasErrors.LeftOverBytesError(leftOverBytes: buffer))
        }
        return .needMoreData
    }

    ///
    /// Attempts to read the header data. Updates the status is successful.
    ///
    /// - parameters:
    ///    - buffer: The buffer containing the integer frame length.
    ///
    private func readNextLengthFieldToState(buffer: inout ByteBuffer) throws {

        // Convert the length field to an integer specifying the length
        guard let lengthFieldValue = self.readFrameLength(for: &buffer) else {
            return
        }

        self.readState = .waitingForFrame(length: lengthFieldValue)
    }
    
    ///
    /// Attempts to read the body data for a given length. Updates the status is successful.
    ///
    /// - parameters:
    ///    - buffer: The buffer containing the frame data.
    ///    - frameLength: The length of the frame data to be read.
    ///
    private func readNextFrame(buffer: inout ByteBuffer, frameLength: Int) throws -> ByteBuffer? {
        
        guard let contentsFieldSlice = buffer.readSlice(length: frameLength) else {
            return nil
        }

        self.readState = .waitingForHeader
        
        return contentsFieldSlice
    }

    ///
    /// Decodes the specified region of the buffer into an unadjusted frame length. The default implementation is
    /// capable of decoding the specified region into an unsigned 8/16/32/64 bit integer.
    ///
    /// - parameters:
    ///    - buffer: The buffer containing the integer frame length.
    ///
    private func readFrameLength(for buffer: inout ByteBuffer) -> Int? {

        switch self.lengthFieldLength {
        case .one:
            return buffer.readInteger(endianness: self.lengthFieldEndianness, as: UInt8.self).map { Int($0) }
        case .two:
            return buffer.readInteger(endianness: self.lengthFieldEndianness, as: UInt16.self).map { Int($0) }
        case .four:
            return buffer.readInteger(endianness: self.lengthFieldEndianness, as: UInt32.self).map { Int($0) }
        case .eight:
            return buffer.readInteger(endianness: self.lengthFieldEndianness, as: UInt64.self).map { Int($0) }
        case .three:
            return buffer.readInteger(byteCount: 3, endianess: self.lengthFieldEndianness, type: UInt32.self).map { Int($0) }
        }
    }
}
