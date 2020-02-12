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

    private struct Compression {
        var algorithm: NIOHTTPDecompression.CompressionAlgorithm
        enum LengthSpecification {
            case contentLength
            case implicit
        }
        var lengthSpecification: LengthSpecification
        var compressedLength: Int
        
        mutating func updateLength(with buffer: ByteBuffer) {
            switch self.lengthSpecification {
            case .contentLength:
                break
            case .implicit:
                self.compressedLength += buffer.readableBytes
            }
        }
    }

    private var compression: Compression? = nil
    private var decompressor: NIOHTTPDecompression.Decompressor

    public init(limit: NIOHTTPDecompression.DecompressionLimit) {
        self.decompressor = NIOHTTPDecompression.Decompressor(limit: limit)
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

            if let algorithm = algorithm {
                do {
                    if let length = length {
                        self.compression = .init(algorithm: algorithm, lengthSpecification: .contentLength, compressedLength: length)
                    } else {
                        self.compression = .init(algorithm: algorithm, lengthSpecification: .implicit, compressedLength: 0)
                    }                    
                    try self.decompressor.initializeDecoder(encoding: algorithm)
                } catch {
                    context.fireErrorCaught(error)
                    return
                }
            }

            context.fireChannelRead(data)
        case .body(var part):
            self.compression?.compressedLength += part.readableBytes
            switch self.compression {
            case .some(let compression):
                while part.readableBytes > 0 {
                    self.compression?.updateLength(with: part)
                    var buffer = context.channel.allocator.buffer(capacity: 16384)
                    do {
                        try self.decompressor.decompress(part: &part, buffer: &buffer, compressedLength: compression.compressedLength)
                    } catch {
                        context.fireErrorCaught(error)
                        return
                    }

                    context.fireChannelRead(self.wrapInboundOut(.body(buffer)))
                }
            case .none:
                context.fireChannelRead(data)
            }
        case .end:
            switch self.compression {
            case .some(_):
                self.decompressor.deinitializeDecoder()
            default:
                break
            }
            context.fireChannelRead(data)
        }
    }
}
