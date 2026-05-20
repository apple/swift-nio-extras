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

private struct Decompressor<InboundHead: HTTPHead> {
    typealias Inbound = HTTPPart<InboundHead, ByteBuffer>

    /// this struct encapsulates the state of a single http response decompression
    private struct Compression {
        /// the used algorithm
        var algorithm: NIOHTTPDecompression.CompressionAlgorithm

        /// the number of already consumed compressed bytes
        var compressedLength: Int
    }

    private var compression: Compression? = nil
    private var decompressor: NIOHTTPDecompression.Decompressor
    private var decompressionComplete: Bool

    init(limit: NIOHTTPDecompression.DecompressionLimit) {
        self.decompressor = NIOHTTPDecompression.Decompressor(limit: limit)
        self.decompressionComplete = false
    }

    mutating func channelRead(context: ChannelHandlerContext, part: Inbound) {
        switch part {
        case .head(let head):
            let contentType = head.headers[canonicalForm: "Content-Encoding"].first?.lowercased()
            let algorithm = NIOHTTPDecompression.CompressionAlgorithm(header: contentType)

            do {
                if let algorithm = algorithm {
                    self.compression = Compression(algorithm: algorithm, compressedLength: 0)
                    try self.decompressor.initializeDecoder()
                }

                context.fireChannelRead(NIOAny(part))
            } catch {
                context.fireErrorCaught(error)
            }
        case .body(var content):
            guard var compression = self.compression else {
                context.fireChannelRead(NIOAny(part))
                return
            }

            do {
                compression.compressedLength += content.readableBytes
                while content.readableBytes > 0 && !self.decompressionComplete {
                    var buffer = context.channel.allocator.buffer(capacity: 16384)
                    let result = try self.decompressor.decompress(
                        part: &content,
                        buffer: &buffer,
                        compressedLength: compression.compressedLength
                    )
                    if result.complete {
                        self.decompressionComplete = true
                    }
                    context.fireChannelRead(NIOAny(Inbound.body(buffer)))
                }

                // assign the changed local property back to the class state
                self.compression = compression

                if content.readableBytes > 0 {
                    context.fireErrorCaught(NIOHTTPDecompression.ExtraDecompressionError.invalidTrailingData)
                }
            } catch {
                context.fireErrorCaught(error)
            }
        case .end:
            if self.compression != nil {
                let wasDecompressionComplete = self.decompressionComplete

                self.decompressor.deinitializeDecoder()
                self.compression = nil
                self.decompressionComplete = false

                if !wasDecompressionComplete {
                    context.fireErrorCaught(NIOHTTPDecompression.ExtraDecompressionError.truncatedData)
                }
            }
            context.fireChannelRead(NIOAny(part))
        }
    }
}
