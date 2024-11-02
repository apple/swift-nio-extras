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

/// A decoder that splits incoming `ByteBuffer`s around line end
/// character(s) (`'\n'` or `'\r\n'`).
///
/// Let's, for example, consider the following received buffer:
///
///     +----+-------+------------+
///     | AB | C\nDE | F\r\nGHI\n |
///     +----+-------+------------+
///
/// A instance of ``LineBasedFrameDecoder`` will split this buffer
/// as follows:
///
///     +-----+-----+-----+
///     | ABC | DEF | GHI |
///     +-----+-----+-----+
///
public class LineBasedFrameDecoder: ByteToMessageDecoder & NIOSingleStepByteToMessageDecoder {
    /// `ByteBuffer` is the expected type passed in.
    public typealias InboundIn = ByteBuffer
    /// `ByteBuffer`s will be passed to the next stage.
    public typealias InboundOut = ByteBuffer

    @available(*, deprecated, message: "No longer used")
    public var cumulationBuffer: ByteBuffer?
    // keep track of the last scan offset from the buffer's reader index (if we didn't find the delimiter)
    private var lastScanOffset = 0

    public init() {}

    /// Decode data in the supplied buffer.
    /// - Parameters:
    ///   - context: Calling cotext
    ///   - buffer: Buffer containing data to decode.
    /// - Returns: State describing if more data is required.
    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        if let frame = try self.findNextFrame(buffer: &buffer) {
            context.fireChannelRead(wrapInboundOut(frame))
            return .continue
        } else {
            return .needMoreData
        }
    }

    /// Decode data in the supplied buffer.
    /// - Parameters:
    ///   - buffer: Buffer containing data to decode.
    /// - Returns: The decoded object or `nil` if we require more bytes.
    public func decode(buffer: inout NIOCore.ByteBuffer) throws -> NIOCore.ByteBuffer? {
        try self.findNextFrame(buffer: &buffer)
    }

    /// Decode all remaining data.
    /// If it is not possible to consume all the data then ``NIOExtrasErrors/LeftOverBytesError`` is reported via `context.fireErrorCaught`
    /// - Parameters:
    ///   - context: Calling context.
    ///   - buffer: Buffer containing the data to decode.
    ///   - seenEOF: Has end of file been seen.
    /// - Returns: Always .needMoreData as all data will be consumed.
    public func decodeLast(
        context: ChannelHandlerContext,
        buffer: inout ByteBuffer,
        seenEOF: Bool
    ) throws -> DecodingState {
        while try self.decode(context: context, buffer: &buffer) == .continue {}
        if buffer.readableBytes > 0 {
            context.fireErrorCaught(NIOExtrasErrors.LeftOverBytesError(leftOverBytes: buffer))
        }
        return .needMoreData
    }

    /// Decode from a `ByteBuffer` when no more data is incoming.
    ///
    /// Like with `decode`, this method will be called in a loop until either `nil` is returned from the method or until the input `ByteBuffer`
    /// has no more readable bytes. If non-`nil` is returned and the `ByteBuffer` contains more readable bytes, this method will immediately
    /// be invoked again.
    ///
    /// If it is not possible to decode remaining bytes into a frame then ``NIOExtrasErrors/LeftOverBytesError`` is thrown.
    /// - Parameters:
    ///   - buffer: Buffer containing the data to decode.
    ///   - seenEOF: Has end of file been seen.
    /// - Returns: The decoded object or `nil` if we require more bytes.
    public func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> InboundOut? {
        let decoded = try self.decode(buffer: &buffer)
        if decoded == nil, buffer.readableBytes > 0 {
            throw NIOExtrasErrors.LeftOverBytesError(leftOverBytes: buffer)
        }
        return decoded
    }

    private func findNextFrame(buffer: inout ByteBuffer) throws -> ByteBuffer? {
        let view = buffer.readableBytesView.dropFirst(self.lastScanOffset)
        // look for the delimiter
        if let delimiterIndex = view.firstIndex(of: 0x0A) {  // '\n'
            let length = delimiterIndex - buffer.readerIndex
            let dropCarriageReturn =
                delimiterIndex > buffer.readableBytesView.startIndex
                && buffer.readableBytesView[delimiterIndex - 1] == 0x0D  // '\r'
            let buff = buffer.readSlice(length: dropCarriageReturn ? length - 1 : length)
            // drop the delimiter (and trailing carriage return if appicable)
            buffer.moveReaderIndex(forwardBy: dropCarriageReturn ? 2 : 1)
            // reset the last scan start index since we found a line
            self.lastScanOffset = 0
            return buff
        }
        // next scan we start where we stopped
        self.lastScanOffset = buffer.readableBytes
        return nil
    }
}

@available(*, unavailable)
extension LineBasedFrameDecoder: Sendable {}
