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
/// Given that the specified header length is 1 byte, there would be a single byte prepended which contains the number 3
///     +---+-----+
///     | A | BCD | ('A' contains 0x03)
///     +---+-----+
/// This initial prepended byte is called the 'length field'.
///
public final class LengthFieldPrepender: ChannelOutboundHandler {
    
    ///
    /// An enumeration to describe the length of a piece of data in bytes.
    /// It is constrained to lengths that can be converted to integer types.
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

    private let lengthFieldLength: LengthFieldPrepender.ByteLength
    private let lengthFieldEndianness: Endianness
    
    private var lengthBuffer: ByteBuffer?

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

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {

        let dataBuffer = self.unwrapOutboundIn(data)
        let dataLength = dataBuffer.readableBytes
        
        guard dataLength <= self.lengthFieldLength.max else {
            promise?.fail(LengthFieldPrependerError.messageDataTooLongForLengthField)
            return
        }
        
        var dataLengthBuffer: ByteBuffer

        if let existingBuffer = self.lengthBuffer {
            dataLengthBuffer = existingBuffer
            dataLengthBuffer.clear()
        } else {
            dataLengthBuffer = context.channel.allocator.buffer(capacity: self.lengthFieldLength.length)
            self.lengthBuffer = dataLengthBuffer
        }

        switch self.lengthFieldLength {
        case .one:
            dataLengthBuffer.writeInteger(UInt8(dataLength), endianness: self.lengthFieldEndianness)
        case .two:
            dataLengthBuffer.writeInteger(UInt16(dataLength), endianness: self.lengthFieldEndianness)
        case .four:
            dataLengthBuffer.writeInteger(UInt32(dataLength), endianness: self.lengthFieldEndianness)
        case .eight:
            dataLengthBuffer.writeInteger(UInt64(dataLength), endianness: self.lengthFieldEndianness)
        }

        context.write(self.wrapOutboundOut(dataLengthBuffer), promise: nil)
        context.write(data, promise: promise)
    }
}
