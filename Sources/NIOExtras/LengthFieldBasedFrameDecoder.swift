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
/// A decoder that splits the received `ByteBuffer` by the number of bytes speicifed in a fixed length header
/// contained within the buffer.
/// For example, if you received the following four fragmented packets:
///     +---+----+------+----+
///     | A | BC | DEFG | HI |
///     +---+----+------+----+
///
/// Given that the specified header length is 1 byte,
/// where the first header specifies 3 bytes while the second header speicifies 4 bytes,
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
    
    private let lengthFieldLength: Int
    private let lengthFieldEndianness: Endianness
    
    /// Create `LengthFieldBasedFrameDecoder` with a given frame length.
    ///
    /// - parameters:
    ///    - lengthFieldLength: The length of the field specifying the remaining length of the frame.
    ///    - lengthFieldEndianness: The endianness of the field specifying the remaining length of the frame.
    ///
    public init(lengthFieldLength: Int, lengthFieldEndianness: Endianness = .little) {
        
        precondition(lengthFieldLength >= 0, "lengthField length must not be negative")
        precondition(lengthFieldLength > 0, "lengthField length must not be zero")
        precondition(lengthFieldLength <= 8, "lengthField length only handles up to 64bit (8 byte)")

        self.lengthFieldLength = lengthFieldLength
        self.lengthFieldEndianness = lengthFieldEndianness
    }
    
    public func decode(ctx: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        
        guard let lengthFieldSlice = buffer.readSlice(length: lengthFieldLength) else {
            return .needMoreData
        }

        // convert the length field to an int specifying the length
        guard let lengthFieldValue = frameLength(for: lengthFieldSlice,
                                                 length: lengthFieldLength,
                                                 endianness: lengthFieldEndianness) else {
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
    ///    - length: The length of the integer contained within the buffer.
    ///    - endianness: The endianness of the integer contained within the buffer.
    ///
    private func frameLength(for buffer: ByteBuffer, length: Int, endianness: Endianness) -> Int? {

        switch length {
        case UInt8.byteWidth:
            return buffer.getInteger(at: 0, endianness: endianness, as: UInt8.self).map { Int($0) }
        case Int16.byteWidth:
            return buffer.getInteger(at: 0, endianness: endianness, as: UInt16.self).map { Int($0) }
        case UInt32.byteWidth:
            return  buffer.getInteger(at: 0, endianness: endianness, as: Int32.self).map { Int($0) }
        case UInt64.byteWidth:
            return buffer.getInteger(at: 0, endianness: endianness, as: UInt64.self).map { Int($0) }
        default:
            return nil
        }
    }
}

///
/// A private protocol extension to FixedWidthInteger for recovering the byte width.
///
extension FixedWidthInteger {

    fileprivate static var byteWidth: Int {
        return bitWidth / 8
    }
}
