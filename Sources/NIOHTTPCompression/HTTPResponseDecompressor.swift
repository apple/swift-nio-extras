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

import CNIOExtrasZlib
import NIO
import NIOHTTP1

public final class NIOHTTPResponseDecompressor: ChannelDuplexHandler, RemovableChannelHandler {
    public typealias InboundIn = HTTPClientResponsePart
    public typealias InboundOut = HTTPClientResponsePart
    public typealias OutboundIn = HTTPClientRequestPart
    public typealias OutboundOut = HTTPClientRequestPart

    /// Specifies how to limit decompression inflation.
    public struct DecompressionLimit {
        enum Limit {
            case none
            case size(Int)
            case ratio(Int)
        }

        var limit: Limit

        /// No limit will be set.
        public static let none = DecompressionLimit(limit: .none)
        /// Limit will be set on the request body size.
        public static func size(_ value: Int) -> DecompressionLimit { return DecompressionLimit(limit: .size(value)) }
        /// Limit will be set on a ratio between compressed body size and decompressed result.
        public static func ratio(_ value: Int) -> DecompressionLimit { return DecompressionLimit(limit: .ratio(value)) }

        func exceeded(compressed: Int, decompressed: Int) -> Bool {
            switch self.limit {
            case .none:
                return false
            case .size(let allowed):
                return compressed > allowed
            case .ratio(let ratio):
                return decompressed > compressed * ratio
            }
        }
    }

    public enum DecompressionError: Error {
        case limit
        case inflationError(Int)
        case initializationError(Int)
    }

    private enum CompressionAlgorithm: String {
        case gzip
        case deflate

        init?(header: String?) {
            switch header {
            case .some("gzip"):
                self = .gzip
            case .some("deflate"):
                self = .deflate
            default:
                return nil
            }
        }

        var window: Int32 {
            switch self {
            case .deflate:
                return 15
            case .gzip:
                return 15 + 16
            }
        }
    }

    private enum State {
        case empty
        case compressed(CompressionAlgorithm, Int)
    }

    private let limit: DecompressionLimit
    private var state = State.empty
    private var stream = z_stream()
    private var inflated = 0

    public init(limit: DecompressionLimit) {
        self.limit = limit
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
            let algorithm = CompressionAlgorithm(header: contentType)

            let length = head.headers[canonicalForm: "Content-Length"].first.flatMap { Int($0) }

            if let algorithm = algorithm, let length = length {
                do {
                    try self.initializeDecoder(encoding: algorithm, length: length)
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
                    do {
                        var buffer = context.channel.allocator.buffer(capacity: 16384)
                        try self.stream.inflatePart(input: &part, output: &buffer)
                        self.inflated += buffer.readableBytes

                        if self.limit.exceeded(compressed: originalLength, decompressed: self.inflated) {
                            context.fireErrorCaught(DecompressionError.limit)
                            return
                        }

                        context.fireChannelRead(self.wrapInboundOut(.body(buffer)))
                    } catch {
                        context.fireErrorCaught(error)
                        return
                    }
                }
            default:
                context.fireChannelRead(data)
            }
        case .end:
            deflateEnd(&self.stream)
            context.fireChannelRead(data)
        }
    }

    private func initializeDecoder(encoding: CompressionAlgorithm, length: Int) throws {
        self.state = .compressed(encoding, length)

        self.stream.zalloc = nil
        self.stream.zfree = nil
        self.stream.opaque = nil

        let rc = CNIOExtrasZlib_inflateInit2(&self.stream, encoding.window)
        guard rc == Z_OK else {
            throw DecompressionError.initializationError(Int(rc))
        }
    }
}

extension z_stream {
    mutating func inflatePart(input: inout ByteBuffer, output: inout ByteBuffer) throws {
        try input.readWithUnsafeMutableReadableBytes { pointer in
            self.avail_in = UInt32(pointer.count)
            self.next_in = CNIOExtrasZlib_voidPtr_to_BytefPtr(pointer.baseAddress!)

            defer {
                self.avail_in = 0
                self.next_in = nil
                self.avail_out = 0
                self.next_out = nil
            }

            try self.inflatePart(to: &output)

            return pointer.count - Int(self.avail_in)
        }
    }

    private mutating func inflatePart(to buffer: inout ByteBuffer) throws {
        try buffer.writeWithUnsafeMutableBytes { pointer in
            self.avail_out = UInt32(pointer.count)
            self.next_out = CNIOExtrasZlib_voidPtr_to_BytefPtr(pointer.baseAddress!)

            let rc = inflate(&self, Z_NO_FLUSH)
            guard rc == Z_OK || rc == Z_STREAM_END else {
                throw NIOHTTPResponseDecompressor.DecompressionError.inflationError(Int(rc))
            }

            return pointer.count - Int(self.avail_out)
        }
    }
}
