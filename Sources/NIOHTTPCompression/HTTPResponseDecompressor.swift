//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import NIOHTTP1

public final class NIOHTTPResponseDecompressor: ChannelDuplexHandler, RemovableChannelHandler {
    public typealias InboundIn = HTTPClientResponsePart
    public typealias InboundOut = HTTPClientResponsePart
    public typealias OutboundIn = HTTPClientRequestPart
    public typealias OutboundOut = HTTPClientRequestPart

    private enum State {
        case empty
        case compressed(NIOHTTPDecompression.CompressionAlgorithm, Int)
    }

    private var state = State.empty
    private var decompressor: Decompressor

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
        switch self.unwrapInboundIn(data) {
        case .head(let head):
            let contentType = head.headers[canonicalForm: "Content-Encoding"].first?.lowercased()
            let algorithm = NIOHTTPDecompression.CompressionAlgorithm(header: contentType)

            let length = head.headers[canonicalForm: "Content-Length"].first.flatMap { Int($0) }

            if let algorithm = algorithm, let length = length {
                do {
                    self.state = .compressed(algorithm, length)
                    try self.decompressor.initializeDecoder(encoding: algorithm, length: length)
                } catch {
                    context.fireErrorCaught(error)
                    return
                }
            }

            context.fireChannelRead(data)
        case .body(var part):
            switch self.state {
            case .compressed(_, let originalLength):
                while part.readableBytes > 0 {
                    var buffer = context.channel.allocator.buffer(capacity: 16384)
                    do {
                        try self.decompressor.decompress(part: &part, buffer: &buffer, originalLength: originalLength)
                    } catch {
                        context.fireErrorCaught(error)
                        return
                    }

                    context.fireChannelRead(self.wrapInboundOut(.body(buffer)))
                }
            default:
                context.fireChannelRead(data)
            }
        case .end:
            switch self.state {
            case .compressed:
                self.decompressor.deinitializeDecoder()
            default:
                break
            }
            context.fireChannelRead(data)
        }
    }
}
