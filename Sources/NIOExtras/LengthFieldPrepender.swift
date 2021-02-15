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
    @discardableResult
    @inlinable
    mutating func write24UInt(
        _ integer: UInt32,
        endianness: Endianness = .big
    ) -> Int {
        assert(integer & 0xFF_FF_FF == integer, "integer value does not fit into 24 bit integer")
        switch endianness {
        case .little:
            return writeInteger(UInt8(integer & 0xFF), endianness: .little) +
                writeInteger(UInt16((integer >> 8) & 0xFF_FF), endianness: .little)
        case .big:
            return writeInteger(UInt16((integer >> 8) & 0xFF_FF), endianness: .big) +
                writeInteger(UInt8(integer & 0xFF), endianness: .big)
        }
    }
}


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
    /// An struct to describe the length of a piece of data in bits
    public struct BitLength {
        fileprivate enum Backing {
            case bits8
            case bits16
            case bits24
            case bits32
            case bits64
        }
        fileprivate let bitLength: Backing

        public static let oneByte: BitLength = BitLength(bitLength: .bits8)
        public static let twoBytes: BitLength = BitLength(bitLength: .bits16)
        public static let threeBytes: BitLength = BitLength(bitLength: .bits24)
        public static let fourBytes: BitLength = BitLength(bitLength: .bits32)
        public static let eightBytes: BitLength = BitLength(bitLength: .bits64)
        
        public static let eightBits: BitLength = BitLength(bitLength: .bits8)
        public static let sixteenBits: BitLength = BitLength(bitLength: .bits16)
        public static let twentyFourBits: BitLength = BitLength(bitLength: .bits24)
        public static let thirtyTwoBits: BitLength = BitLength(bitLength: .bits32)
        public static let sixtyFourBits: BitLength = BitLength(bitLength: .bits64)
        
        fileprivate var length: Int {
            switch bitLength {
            case .bits8:
                return 1
            case .bits16:
                return 2
            case .bits24:
                return 3
            case .bits32:
                return 4
            case .bits64:
                return 8
            }
        }
        
        fileprivate var max: UInt {
            switch bitLength {
            case .bits8:
                return UInt(UInt8.max)
            case .bits16:
                return UInt(UInt16.max)
            case .bits24:
                return (UInt(UInt16.max) << 8) &+ UInt(UInt8.max)
            case .bits32:
                return UInt(UInt32.max)
            case .bits64:
                return UInt(UInt64.max)
            }
        }
    }
    ///
    /// An enumeration to describe the length of a piece of data in bytes.
    ///
    public enum ByteLength {
        case one
        case two
        case four
        case eight
        
        fileprivate var bitLength: BitLength {
            switch self {
            case .one: return .oneByte
            case .two: return .twoBytes
            case .four: return .fourBytes
            case .eight: return .eightBytes
            }
        }
    }

    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    private let lengthFieldLength: LengthFieldPrepender.BitLength
    private let lengthFieldEndianness: Endianness
    
    private var lengthBuffer: ByteBuffer?

    /// Create `LengthFieldPrepender` with a given length field length.
    ///
    /// - parameters:
    ///    - lengthFieldLength: The length of the field specifying the remaining length of the frame.
    ///    - lengthFieldEndianness: The endianness of the field specifying the remaining length of the frame.
    ///
    public convenience init(lengthFieldLength: ByteLength, lengthFieldEndianness: Endianness = .big) {
        self.init(lengthFieldBitLength: lengthFieldLength.bitLength, lengthFieldEndianness: lengthFieldEndianness)
    }
    public init(lengthFieldBitLength: BitLength, lengthFieldEndianness: Endianness = .big) {
        // The value contained in the length field must be able to be represented by an integer type on the platform.
        // ie. .eight == 64bit which would not fit into the Int type on a 32bit platform.
        precondition(lengthFieldBitLength.length <= Int.bitWidth/8)
        
        self.lengthFieldLength = lengthFieldBitLength
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

        switch self.lengthFieldLength.bitLength {
        case .bits8:
            dataLengthBuffer.writeInteger(UInt8(dataLength), endianness: self.lengthFieldEndianness)
        case .bits16:
            dataLengthBuffer.writeInteger(UInt16(dataLength), endianness: self.lengthFieldEndianness)
        case .bits24:
            dataLengthBuffer.write24UInt(UInt32(dataLength), endianness: self.lengthFieldEndianness)
        case .bits32:
            dataLengthBuffer.writeInteger(UInt32(dataLength), endianness: self.lengthFieldEndianness)
        case .bits64:
            dataLengthBuffer.writeInteger(UInt64(dataLength), endianness: self.lengthFieldEndianness)
        }

        context.write(self.wrapOutboundOut(dataLengthBuffer), promise: nil)
        context.write(data, promise: promise)
    }
}
