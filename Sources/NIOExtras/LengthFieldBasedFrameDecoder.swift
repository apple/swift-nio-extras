//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

extension ByteBuffer {
    @inlinable
    mutating func get24UInt(
        at index: Int,
        endianness: Endianness = .big
    ) -> UInt32? {
        let mostSignificant: UInt16
        let leastSignificant: UInt8
        switch endianness {
        case .big:
            guard let uint16 = self.getInteger(at: index, endianness: .big, as: UInt16.self),
                let uint8 = self.getInteger(at: index + 2, endianness: .big, as: UInt8.self)
            else { return nil }
            mostSignificant = uint16
            leastSignificant = uint8
        case .little:
            guard let uint8 = self.getInteger(at: index, endianness: .little, as: UInt8.self),
                let uint16 = self.getInteger(at: index + 1, endianness: .little, as: UInt16.self)
            else { return nil }
            mostSignificant = uint16
            leastSignificant = uint8
        }
        return (UInt32(mostSignificant) << 8) &+ UInt32(leastSignificant)
    }
    @inlinable
    mutating func read24UInt(
        endianness: Endianness = .big
    ) -> UInt32? {
        guard let integer = get24UInt(at: self.readerIndex, endianness: endianness) else { return nil }
        self.moveReaderIndex(forwardBy: 3)
        return integer
    }
}

public enum NIOLengthFieldBasedFrameDecoderError: Error {
    /// This error can be thrown by ``LengthFieldBasedFrameDecoder`` if the length field value is larger than `Int.max`
    case lengthFieldValueTooLarge
    /// This error can be thrown by ``LengthFieldBasedFrameDecoder`` if the length field value is larger than `LengthFieldBasedFrameDecoder.maxSupportedLengthFieldSize`
    case lengthFieldValueLargerThanMaxSupportedSize
    /// The adjusted frame length is negative or cannot be represented by `Int`.
    case invalidAdjustedFrameLength
}

///
/// A decoder that splits the received `ByteBuffer` by the number of bytes specified in a fixed length header
/// contained within the buffer.
///
/// For example, if you received the following four fragmented packets:
///
///     +---+----+------+----+
///     | A | BC | DEFG | HI |
///     +---+----+------+----+
///
/// Given that the specified header length is 1 byte,
/// where the first header specifies 3 bytes while the second header specifies 4 bytes,
/// a ``LengthFieldBasedFrameDecoder`` will decode them into the following packets:
///
///     +-----+------+
///     | BCD | FGHI |
///     +-----+------+
///
/// 'A' and 'E' will be the headers and will not be passed forward.
///
public final class LengthFieldBasedFrameDecoder: ByteToMessageDecoder {
    /// Maximum supported length field size in bytes of ``LengthFieldBasedFrameDecoder`` and is currently `Int32.max`
    public static let maxSupportedLengthFieldSize: Int = Int(Int32.max)

    /// An enumeration to describe the length of a piece of data in bytes.
    public enum ByteLength: Sendable {
        /// One byte
        case one
        /// Two bytes
        case two
        /// Four bytes
        case four
        /// Eight bytes
        case eight

        fileprivate var bitLength: NIOLengthFieldBitLength {
            switch self {
            case .one: return .oneByte
            case .two: return .twoBytes
            case .four: return .fourBytes
            case .eight: return .eightBytes
            }
        }
    }

    /// The decoder has two distinct sections of data to read.
    /// Each must be fully present before it is considered as read.
    /// During the time when it is not present the decoder must wait. ``DecoderReadState`` details that waiting state.
    private enum DecoderReadState {
        // Expending a header next.
        case waitingForHeader
        // Expecting the frame next.
        case waitingForFrame(length: Int)
    }

    /// Incoming data is in `ByteBuffer`
    public typealias InboundIn = ByteBuffer
    /// `ByteBuffer` is type passed to next stage.
    public typealias InboundOut = ByteBuffer

    @available(*, deprecated, message: "No longer used")
    public var cumulationBuffer: ByteBuffer?
    private var readState: DecoderReadState = .waitingForHeader

    private let lengthFieldLength: NIOLengthFieldBitLength
    private let lengthFieldEndianness: Endianness
    private let lengthAdjustment: Int

    /// Create `LengthFieldBasedFrameDecoder` with a given frame length.
    ///
    /// - parameters:
    ///    - lengthFieldLength: The length of the field specifying the remaining length of the frame.
    ///    - lengthFieldEndianness: The endianness of the field specifying the remaining length of the frame.
    public convenience init(lengthFieldLength: ByteLength, lengthFieldEndianness: Endianness = .big) {
        self.init(lengthFieldBitLength: lengthFieldLength.bitLength, lengthFieldEndianness: lengthFieldEndianness)
    }

    /// Create `LengthFieldBasedFrameDecoder` with a given frame length.
    ///
    /// - parameters:
    ///    - lengthFieldBitLength: The length of the field specifying the remaining length of the frame.
    ///    - lengthFieldEndianness: The endianness of the field specifying the remaining length of the frame.
    public convenience init(lengthFieldBitLength: NIOLengthFieldBitLength, lengthFieldEndianness: Endianness = .big) {
        self.init(
            lengthFieldBitLength: lengthFieldBitLength,
            lengthFieldEndianness: lengthFieldEndianness,
            lengthAdjustment: 0
        )
    }

    /// Create a decoder that adjusts the declared length before reading the frame body.
    ///
    /// - Parameters:
    ///   - lengthFieldLength: The size of the length field.
    ///   - lengthFieldEndianness: The endianness of the length field.
    ///   - lengthAdjustment: The number of bytes to add to the declared length.
    ///     For a protocol that includes a two-byte length field in its declared length, use `-2`.
    public convenience init(
        lengthFieldLength: ByteLength,
        lengthFieldEndianness: Endianness = .big,
        lengthAdjustment: Int
    ) {
        self.init(
            lengthFieldBitLength: lengthFieldLength.bitLength,
            lengthFieldEndianness: lengthFieldEndianness,
            lengthAdjustment: lengthAdjustment
        )
    }

    /// Create a decoder that adjusts the declared length before reading the frame body.
    ///
    /// - Parameters:
    ///   - lengthFieldBitLength: The size of the length field.
    ///   - lengthFieldEndianness: The endianness of the length field.
    ///   - lengthAdjustment: The number of bytes to add to the declared length.
    ///     Use the negative size of the length field when the declared length includes that field.
    public init(
        lengthFieldBitLength: NIOLengthFieldBitLength,
        lengthFieldEndianness: Endianness = .big,
        lengthAdjustment: Int
    ) {
        self.lengthFieldLength = lengthFieldBitLength
        self.lengthFieldEndianness = lengthFieldEndianness
        self.lengthAdjustment = lengthAdjustment
    }

    /// Decode supplied data.
    /// - Parameters:
    ///   - context: Calling context.
    ///   - buffer: data to decode.
    /// - Returns: `DecodingState` describing what's needed next.
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

    /// Decode all data supplied.  No more is expected after this.
    /// If all data is not exactly consumed reports and error through `context.fireErrorCaught`
    /// - Parameters:
    ///   - context: Calling context.
    ///   - buffer: The data to decode
    ///   - seenEOF: If End of File has been seen.
    /// - Returns: .needMoreData always as all data has been consumed.
    public func decodeLast(
        context: ChannelHandlerContext,
        buffer: inout ByteBuffer,
        seenEOF: Bool
    ) throws -> DecodingState {
        // we'll just try to decode as much as we can as usually
        while case .continue = try self.decode(context: context, buffer: &buffer) {}
        if buffer.readableBytes > 0 {
            context.fireErrorCaught(NIOExtrasErrors.LeftOverBytesError(leftOverBytes: buffer))
        }
        return .needMoreData
    }

    /// Attempts to read the header data. Updates the status is successful.
    ///
    /// - parameters:
    ///    - buffer: The buffer containing the integer frame length.
    private func readNextLengthFieldToState(buffer: inout ByteBuffer) throws {

        // Convert the length field to an integer specifying the length
        guard let lengthFieldValue = try self.readFrameLength(for: &buffer) else {
            return
        }

        let (frameLength, overflow) = lengthFieldValue.addingReportingOverflow(self.lengthAdjustment)
        guard !overflow, frameLength >= 0 else {
            throw NIOLengthFieldBasedFrameDecoderError.invalidAdjustedFrameLength
        }
        guard frameLength <= LengthFieldBasedFrameDecoder.maxSupportedLengthFieldSize else {
            throw NIOLengthFieldBasedFrameDecoderError.lengthFieldValueLargerThanMaxSupportedSize
        }
        self.readState = .waitingForFrame(length: frameLength)
    }

    /// Attempts to read the body data for a given length. Updates the status is successful.
    ///
    /// - parameters:
    ///    - buffer: The buffer containing the frame data.
    ///    - frameLength: The length of the frame data to be read.
    private func readNextFrame(buffer: inout ByteBuffer, frameLength: Int) throws -> ByteBuffer? {

        guard let contentsFieldSlice = buffer.readSlice(length: frameLength) else {
            return nil
        }

        self.readState = .waitingForHeader

        return contentsFieldSlice
    }

    /// Decodes the specified region of the buffer into an unadjusted frame length. The default implementation is
    /// capable of decoding the specified region into an unsigned 8/16/24/32/64 bit integer.
    ///
    /// - parameters:
    ///    - buffer: The buffer containing the integer frame length.
    private func readFrameLength(for buffer: inout ByteBuffer) throws -> Int? {
        let frameLength: Int?
        switch self.lengthFieldLength.bitLength {
        case .bits8:
            frameLength = buffer.readInteger(endianness: self.lengthFieldEndianness, as: UInt8.self).map { Int($0) }
        case .bits16:
            frameLength = buffer.readInteger(endianness: self.lengthFieldEndianness, as: UInt16.self).map { Int($0) }
        case .bits24:
            frameLength = buffer.read24UInt(endianness: self.lengthFieldEndianness).map { Int($0) }
        case .bits32:
            frameLength = try buffer.readInteger(endianness: self.lengthFieldEndianness, as: UInt32.self).map {
                guard let size = Int(exactly: $0) else {
                    throw NIOLengthFieldBasedFrameDecoderError.lengthFieldValueTooLarge
                }
                return size
            }
        case .bits64:
            frameLength = try buffer.readInteger(endianness: self.lengthFieldEndianness, as: UInt64.self).map {
                guard let size = Int(exactly: $0) else {
                    throw NIOLengthFieldBasedFrameDecoderError.lengthFieldValueTooLarge
                }
                return size
            }
        }

        return frameLength
    }
}

@available(*, unavailable)
extension LengthFieldBasedFrameDecoder: Sendable {}
