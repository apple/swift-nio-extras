//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019-2026 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOHTTP1

/// Channel hander to decompress incoming HTTP data.
public final class NIOHTTPRequestDecompressor: ChannelDuplexHandler, RemovableChannelHandler {
    /// Expect to receive `HTTPServerRequestPart` from the network
    public typealias InboundIn = HTTPServerRequestPart
    /// Pass `HTTPServerRequestPart` to the next pipeline state in an inbound direction.
    public typealias InboundOut = HTTPServerRequestPart
    /// Pass through `HTTPServerResponsePart` outbound.
    public typealias OutboundIn = HTTPServerResponsePart
    /// Pass through `HTTPServerResponsePart` outbound.
    public typealias OutboundOut = HTTPServerResponsePart

    private var decompressor: Decompressor<HTTPRequestHead>

    /// Initialise
    /// - Parameter limit: Limit on the amount of decompression allowed.
    public init(limit: NIOHTTPDecompression.DecompressionLimit) {
        self.decompressor = Decompressor(limit: limit)
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.decompressor.channelRead(context: context, part: Self.unwrapInboundIn(data))
    }
}

@available(*, unavailable)
extension NIOHTTPRequestDecompressor: Sendable {}

/// Duplex channel handler which will accept deflate and gzip encoded responses and decompress them.
public final class NIOHTTPResponseDecompressor: ChannelDuplexHandler, RemovableChannelHandler {
    /// Expect `HTTPClientResponsePart` inbound.
    public typealias InboundIn = HTTPClientResponsePart
    /// Sends `HTTPClientResponsePart` to the next pipeline stage inbound.
    public typealias InboundOut = HTTPClientResponsePart
    /// Expect `HTTPClientRequestPart` outbound.
    public typealias OutboundIn = HTTPClientRequestPart
    /// Send `HTTPClientRequestPart` to the next stage outbound.
    public typealias OutboundOut = HTTPClientRequestPart

    private var decompressor: Decompressor<HTTPResponseHead>

    /// Initialise
    /// - Parameter limit: Limit on the amount of decompression allowed.
    public init(limit: NIOHTTPDecompression.DecompressionLimit) {
        self.decompressor = Decompressor(limit: limit)
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let request = self.unwrapOutboundIn(data)
        switch request {
        case .head(var head):
            if head.headers.contains(name: "Accept-Encoding") {
                context.write(data, promise: promise)
            } else {
                head.headers.replaceOrAdd(name: "Accept-Encoding", value: "deflate, gzip")
                context.write(self.wrapOutboundOut(.head(head)), promise: promise)
            }
        default:
            context.write(data, promise: promise)
        }
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.decompressor.channelRead(context: context, part: Self.unwrapInboundIn(data))
    }
}

@available(*, unavailable)
extension NIOHTTPResponseDecompressor: Sendable {}

// MARK: - Shared implementation -

private protocol HTTPHead: Equatable {
    var headers: HTTPHeaders { get }
}

extension HTTPRequestHead: HTTPHead {}
extension HTTPResponseHead: HTTPHead {}

/// This class encapsulates the state of a single http message decompression
private final class HTTPDecompressionDecoder: NIOSingleStepByteToMessageDecoder {
    typealias InboundOut = ByteBuffer

    private let allocator: ByteBufferAllocator
    private var decompressor: NIOHTTPDecompression.Decompressor
    /// The number of already consumed compressed bytes
    private var compressedLength: Int
    private var complete: Bool

    init(limit: NIOHTTPDecompression.DecompressionLimit, allocator: ByteBufferAllocator) throws {
        self.allocator = allocator
        self.decompressor = NIOHTTPDecompression.Decompressor(limit: limit)
        self.compressedLength = 0
        self.complete = false
        try self.decompressor.initializeDecoder()
    }

    deinit {
        self.decompressor.deinitializeDecoder()
    }

    func decode(buffer: inout ByteBuffer) throws -> ByteBuffer? {
        guard !self.complete, buffer.readableBytes > 0 else {
            return nil
        }

        let compressedLength = self.compressedLength + buffer.readableBytes
        var output = self.allocator.buffer(capacity: 16384)
        let readableBytesBefore = buffer.readableBytes
        let result = try self.decompressor.decompress(
            part: &buffer,
            buffer: &output,
            compressedLength: compressedLength
        )
        self.compressedLength += readableBytesBefore - buffer.readableBytes
        if result.complete {
            self.complete = true
        }
        return output
    }

    func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> ByteBuffer? {
        if let output = try self.decode(buffer: &buffer) {
            return output
        }
        if !self.complete {
            throw NIOHTTPDecompression.ExtraDecompressionError.truncatedData
        }
        return nil
    }
}

private final class Decompressor<InboundHead: HTTPHead> {
    typealias Inbound = HTTPPart<InboundHead, ByteBuffer>

    private let limit: NIOHTTPDecompression.DecompressionLimit
    private var processor: NIOSingleStepByteToMessageProcessor<HTTPDecompressionDecoder>?

    init(limit: NIOHTTPDecompression.DecompressionLimit) {
        self.limit = limit
        self.processor = nil
    }

    func channelRead(context: ChannelHandlerContext, part: Inbound) {
        switch part {
        case .head(let head):
            let contentType = head.headers[canonicalForm: "Content-Encoding"].first?.lowercased()
            let algorithm = NIOHTTPDecompression.CompressionAlgorithm(header: contentType)

            do {
                if algorithm != nil {
                    let decoder = try HTTPDecompressionDecoder(
                        limit: self.limit,
                        allocator: context.channel.allocator
                    )
                    self.processor = NIOSingleStepByteToMessageProcessor(decoder)
                }

                context.fireChannelRead(NIOAny(part))
            } catch {
                context.fireErrorCaught(error)
            }
        case .body(let buffer):
            guard let processor = self.processor else {
                context.fireChannelRead(NIOAny(part))
                return
            }

            do {
                try processor.process(buffer: buffer) { output in
                    context.fireChannelRead(NIOAny(Inbound.body(output)))
                }

                // bytes left after the compressed body are invalid trailing data
                if processor.unprocessedBytes > 0 {
                    context.fireErrorCaught(NIOHTTPDecompression.ExtraDecompressionError.invalidTrailingData)
                }
            } catch {
                context.fireErrorCaught(error)
            }
        case .end:
            if let processor = self.processor {
                self.processor = nil

                do {
                    try processor.finishProcessing(seenEOF: true) { output in
                        context.fireChannelRead(NIOAny(Inbound.body(output)))
                    }
                } catch {
                    context.fireErrorCaught(error)
                }
            }
            context.fireChannelRead(NIOAny(part))
        }
    }
}
