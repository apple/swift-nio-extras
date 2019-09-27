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

import CNIOExtrasZlib
import NIO
import NIOHTTP1

/// Specifies how to limit decompression inflation.
public enum DecompressionLimit {
    /// No limit will be set.
    case none
    /// Limit will be set on the request body size.
    case size(Int)
    /// Limit will be set on a ratio between compressed body size and decompressed result.
    case ratio(Int)

    func exceeded(compressed: Int, decompressed: Int) -> Bool {
        switch self {
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
    case inflationError(Int32)
    case initializationError(Int32)
}

public final class HTTPResponseDecompressor: ChannelDuplexHandler, RemovableChannelHandler {
    public typealias InboundIn = HTTPClientResponsePart
    public typealias InboundOut = HTTPClientResponsePart
    public typealias OutboundIn = HTTPClientRequestPart
    public typealias OutboundOut = HTTPClientRequestPart

    private enum CompressionAlgorithm: String {
        case gzip
        case deflate
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
            let algorithm: CompressionAlgorithm?
            let contentType = head.headers[canonicalForm: "Content-Encoding"].first?.lowercased()
            if contentType == "gzip" {
                algorithm = .gzip
            } else if contentType == "deflate" {
                algorithm = .deflate
            } else {
                algorithm = nil
            }

            let length = head.headers[canonicalForm: "Content-Length"].first.flatMap { Int($0) }

            if let algorithm = algorithm, let length = length {
                do {
                    try self.initializeDecoder(encoding: algorithm, length: length)
                } catch {
                    context.fireErrorCaught(error)
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

        let window: Int32
        switch encoding {
        case .gzip:
            window = 15 + 16
        default:
            window = 15
        }

        let rc = CNIOExtrasZlib_inflateInit2(&self.stream, window)
        guard rc == Z_OK else {
            throw DecompressionError.initializationError(rc)
        }
    }
}

extension z_stream {
    mutating func inflatePart(input: inout ByteBuffer, output: inout ByteBuffer) throws {
        try input.readWithUnsafeMutableReadableBytes { (dataPtr: UnsafeMutableRawBufferPointer) -> Int in
            let typedPtr = dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let typedDataPtr = UnsafeMutableBufferPointer(start: typedPtr, count: dataPtr.count)

            self.avail_in = UInt32(typedDataPtr.count)
            self.next_in = typedDataPtr.baseAddress!

            defer {
                self.avail_in = 0
                self.next_in = nil
                self.avail_out = 0
                self.next_out = nil
            }

            try self.inflatePart(to: &output)

            return typedDataPtr.count - Int(self.avail_in)
        }
    }

    private mutating func inflatePart(to buffer: inout ByteBuffer) throws {
        try buffer.writeWithUnsafeMutableBytes { outputPtr in
            let typedOutputPtr = UnsafeMutableBufferPointer(start: outputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), count: outputPtr.count)

            self.avail_out = UInt32(typedOutputPtr.count)
            self.next_out = typedOutputPtr.baseAddress!

            let rc = inflate(&self, Z_NO_FLUSH)
            guard rc == Z_OK || rc == Z_STREAM_END else {
                throw DecompressionError.inflationError(rc)
            }

            return typedOutputPtr.count - Int(self.avail_out)
        }
    }
}
