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

extension ByteBuffer {
    @inlinable
    mutating func get24UInt(
        endianness: Endianness = .big
    ) -> UInt32? {
        let mostSignificant: UInt16
        let leastSignificant: UInt8
        switch endianness {
        case .big:
            guard let uint16 = self.getInteger(at: readerIndex, endianness: .big, as: UInt16.self),
                  let uint8 = self.getInteger(at: readerIndex + 2, endianness: .big, as: UInt8.self) else { return nil }
            mostSignificant = uint16
            leastSignificant = uint8
        case .little:
            guard let uint8 = self.getInteger(at: readerIndex, endianness: .little, as: UInt8.self),
                  let uint16 = self.getInteger(at: readerIndex + 1, endianness: .little, as: UInt16.self) else { return nil }
            mostSignificant = uint16
            leastSignificant = uint8
        }
        return (UInt32(mostSignificant) << 8) &+ UInt32(leastSignificant)
    }
    @inlinable
    mutating func read24UInt(
        endianness: Endianness = .big
    ) -> UInt32? {
        guard let integer = get24UInt(endianness: endianness) else { return nil }
        self.moveReaderIndex(forwardBy: 3)
        return integer
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
    /// capable of decoding the specified region into an unsigned 8/16/24/32/64 bit integer.
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
        case .three:
            return buffer.read24UInt(endianness: self.lengthFieldEndianness).map { Int($0) }
        case .four:
            return buffer.readInteger(endianness: self.lengthFieldEndianness, as: UInt32.self).map { Int($0) }
        case .eight:
            return buffer.readInteger(endianness: self.lengthFieldEndianness, as: UInt64.self).map { Int($0) }
        }
    }
}
