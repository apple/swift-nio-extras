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

///
/// An enumeration to describe the length of a piece of data in bytes.
/// It is contained to lengths that can be converted to integer types.
///
public enum ByteLength {
    case one
    case two
    case four
    case eight
}

extension ByteLength {
   
    fileprivate var length: Int {

        switch self {
        case .one:
            return 1
        case .two:
            return 2
        case .four:
            return 4
        case .eight:
            return 8
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

    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    
    public var cumulationBuffer: ByteBuffer?
    
    private let lengthFieldLength: ByteLength
    private let lengthFieldEndianness: Endianness
    
    /// Create `LengthFieldBasedFrameDecoder` with a given frame length.
    ///
    /// - parameters:
    ///    - lengthFieldLength: The length of the field specifying the remaining length of the frame.
    ///    - lengthFieldEndianness: The endianness of the field specifying the remaining length of the frame.
    ///
    public init(lengthFieldLength: ByteLength, lengthFieldEndianness: Endianness = .big) {
        self.lengthFieldLength = lengthFieldLength
        self.lengthFieldEndianness = lengthFieldEndianness
    }
    
    public func decode(ctx: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        
        guard let lengthFieldSlice = buffer.readSlice(length: self.lengthFieldLength.length) else {
            return .needMoreData
        }

        // convert the length field to an int specifying the length
        guard let lengthFieldValue = self.frameLength(for: lengthFieldSlice) else {
            return .needMoreData
        }

        guard let contentsFieldSlice = buffer.readSlice(length: lengthFieldValue) else {
            return .needMoreData
        }

        ctx.fireChannelRead(self.wrapInboundOut(contentsFieldSlice))

        return .continue
    }
    
    public func handlerRemoved(ctx: ChannelHandlerContext) {
        if let buffer = cumulationBuffer, buffer.readableBytes > 0 {
            ctx.fireErrorCaught(NIOExtrasErrors.LeftOverBytesError(leftOverBytes: buffer))
        }
    }

    ///
    /// Decodes the specified region of the buffer into an unadjusted frame length. The default implementation is
    /// capable of decoding the specified region into an unsigned 8/16/32/64 bit integer.
    /// - parameters:
    ///    - buffer: The buffer containing the integer frame length
    ///
    private func frameLength(for buffer: ByteBuffer) -> Int? {

        switch self.lengthFieldLength {
        case .one:
            return buffer.getInteger(at: 0, endianness: self.lengthFieldEndianness, as: UInt8.self).map { Int($0) }
        case .two:
            return buffer.getInteger(at: 0, endianness: self.lengthFieldEndianness, as: UInt16.self).map { Int($0) }
        case .four:
            return buffer.getInteger(at: 0, endianness: self.lengthFieldEndianness, as: UInt32.self).map { Int($0) }
        case .eight:
            return buffer.getInteger(at: 0, endianness: self.lengthFieldEndianness, as: UInt64.self).map { Int($0) }
        }
    }
}
