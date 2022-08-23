//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019-2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CNIOExtrasZlib
import NIOHTTP1
import NIOCore

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

    private struct Compression {
        let algorithm: NIOHTTPDecompression.CompressionAlgorithm
        let contentLength: Int
    }

    private var decompressor: NIOHTTPDecompression.Decompressor
    private var compression: Compression?

    /// Initialise with limits.
    /// - Parameter limit: Limit to how much inflation can occur to protect against bad cases.
    public init(limit: NIOHTTPDecompression.DecompressionLimit) {
        self.decompressor = NIOHTTPDecompression.Decompressor(limit: limit)
        self.compression = nil
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let request = self.unwrapInboundIn(data)

        switch request {
        case .head(let head):
            if
                let encoding = head.headers[canonicalForm: "Content-Encoding"].first?.lowercased(),
                let algorithm = NIOHTTPDecompression.CompressionAlgorithm(header: encoding),
                let length = head.headers[canonicalForm: "Content-Length"].first.flatMap({ Int($0) })
            {
                do {
                    try self.decompressor.initializeDecoder(encoding: algorithm)
                    self.compression = Compression(algorithm: algorithm, contentLength: length)
                } catch let error {
                    context.fireErrorCaught(error)
                    return
                }
            }

            context.fireChannelRead(data)
        case .body(var part):
            guard let compression = self.compression else {
                context.fireChannelRead(data)
                return
            }

            while part.readableBytes > 0 {
                do {
                    var buffer = context.channel.allocator.buffer(capacity: 16384)
                    try self.decompressor.decompress(part: &part, buffer: &buffer, compressedLength: compression.contentLength)

                    context.fireChannelRead(self.wrapInboundOut(.body(buffer)))
                } catch let error {
                    context.fireErrorCaught(error)
                    return
                }
            }
        case .end:
            if self.compression != nil {
                self.decompressor.deinitializeDecoder()
                self.compression = nil
            }

            context.fireChannelRead(data)
        }
    }
}

#if swift(>=5.6)
@available(*, unavailable)
extension NIOHTTPRequestDecompressor: Sendable {}
#endif
