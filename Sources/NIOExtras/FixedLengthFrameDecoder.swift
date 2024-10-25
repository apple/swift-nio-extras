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

///
/// A decoder that splits the received `ByteBuffer` by a fixed number
/// of bytes. For example, if you received the following four fragmented packets:
///
///     +---+----+------+----+
///     | A | BC | DEFG | HI |
///     +---+----+------+----+
///
/// A ``FixedLengthFrameDecoder`` will decode them into the
/// following three packets with the fixed length:
///
///     +-----+-----+-----+
///     | ABC | DEF | GHI |
///     +-----+-----+-----+
///
public final class FixedLengthFrameDecoder: ByteToMessageDecoder {
    /// Data type we receive.
    public typealias InboundIn = ByteBuffer
    /// Data type we send to the next stage.
    public typealias InboundOut = ByteBuffer

    @available(*, deprecated, message: "No longer used")
    public var cumulationBuffer: ByteBuffer?

    private let frameLength: Int

    /// Create `FixedLengthFrameDecoder` with a given frame length.
    ///
    /// - parameters:
    ///    - frameLength: The length of a frame.
    public init(frameLength: Int) {
        self.frameLength = frameLength
    }

    /// Get a frame of data and `fireChannelRead` if sufficient data exists in the buffer.
    /// - Parameters:
    ///   - context: Calling context.
    ///   - buffer: Buffer containing data.
    /// - Returns: Status detailing if more data is required or if a successful decode occurred.
    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard let slice = buffer.readSlice(length: frameLength) else {
            return .needMoreData
        }

        context.fireChannelRead(self.wrapInboundOut(slice))
        return .continue
    }

    /// Repeatedly decode frames until there is not enough data to decode any more.
    /// Reports an error through `fireErrorCaught` if this doesn't empty the buffer exactly.
    /// - Parameters:
    ///   - context: Calling context
    ///   - buffer: Buffer containing data.
    ///   - seenEOF: If end of file has been seen.
    /// - Returns: needMoreData always as all data is consumed.
    public func decodeLast(
        context: ChannelHandlerContext,
        buffer: inout ByteBuffer,
        seenEOF: Bool
    ) throws -> DecodingState {
        while case .continue = try self.decode(context: context, buffer: &buffer) {}
        if buffer.readableBytes > 0 {
            context.fireErrorCaught(NIOExtrasErrors.LeftOverBytesError(leftOverBytes: buffer))
        }
        return .needMoreData
    }
}

@available(*, unavailable)
extension FixedLengthFrameDecoder: Sendable {}
