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

public enum LengthFieldPrependerError: Error {
    case messageDataTooLongForLengthField
}

///
/// An encoder that takes a `ByteBuffer` message and prepends the number of bytes in the message.
/// The length field is always the same fixed length specified on construction.
/// These bytes contain a binary specification of the message size.
///
/// For example, if you received a packet with the 3 byte length (BCD)...
/// Given that the specified header length is 1 byte, there would be a single byte appended which contains the number 3
///     +---+-----+
///     | A | BCD | ('A' contains 0x0003)
///     +---+-----+
/// This initial appended byte is called the 'length field'.
///
public final class LengthFieldPrepender: ChannelOutboundHandler {
    
    ///
    /// An enumeration to describe the length of a piece of data in bytes.
    /// It is contained to lengths that can be converted to integer types.
    ///
    public enum ByteLength {
        case one
        case two
        case four
        case eight
       
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
        
        fileprivate var max: UInt {
            
            switch self {
            case .one:
                return UInt(UInt8.max)
            case .two:
                return UInt(UInt16.max)
            case .four:
                return UInt(UInt32.max)
            case .eight:
                return UInt(UInt64.max)
            }
        }
    }

    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    private let lengthFieldLength: ByteLength
    private let lengthFieldEndianness: Endianness

    /// Create `LengthFieldPrepender` with a given length field length.
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

    public func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {

        let dataBuffer = self.unwrapOutboundIn(data)
        let dataLength = dataBuffer.readableBytes
        
        guard dataLength <= self.lengthFieldLength.max else {
            promise?.fail(error: LengthFieldPrependerError.messageDataTooLongForLengthField)
            return
        }

        var lengthBuffer = ctx.channel.allocator.buffer(capacity: self.lengthFieldLength.length)

        switch self.lengthFieldLength {
        case .one:
            lengthBuffer.write(integer: UInt8(dataLength), endianness: self.lengthFieldEndianness)
        case .two:
            lengthBuffer.write(integer: UInt16(dataLength), endianness: self.lengthFieldEndianness)
        case .four:
            lengthBuffer.write(integer: UInt32(dataLength), endianness: self.lengthFieldEndianness)
        case .eight:
            lengthBuffer.write(integer: UInt64(dataLength), endianness: self.lengthFieldEndianness)
        }
        
        ctx.write(self.wrapOutboundOut(lengthBuffer), promise: nil)
        ctx.write(data, promise: promise)
    }
}
