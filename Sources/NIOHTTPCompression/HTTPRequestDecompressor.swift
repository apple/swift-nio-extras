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
import NIOHTTP1
import NIO

public final class NIOHTTPRequestDecompressor: ChannelDuplexHandler, RemovableChannelHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias InboundOut = HTTPServerRequestPart
    public typealias OutboundIn = HTTPServerResponsePart
    public typealias OutboundOut = HTTPServerResponsePart

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

    public enum DecompressionLimit {
        case none
        case size(Int)
        case ratio(Int)

        func exceeded(compressed: Int, decompressed: Int) -> Bool {
            switch self {
            case .none: return false
            case let .size(allowed): return compressed > allowed
            case let .ratio(ratio): return decompressed > compressed * ratio
            }
        }
    }

    public enum DecompressionError: Error {
        case limit
        case inflationError(Int32)
        case initalizationError(Int32)
    }

    private struct Compression {
        let algorithm: CompressionAlgorithm
        let contentLength: Int
    }

    private let limit: DecompressionLimit

    private var compression: Compression?
    private var inflated: Int
    private var stream: z_stream

    public init(limit: DecompressionLimit) {
        self.limit = limit

        self.compression = nil
        self.inflated = 0
        self.stream = z_stream()
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let request = self.unwrapInboundIn(data)

        switch request {
        case .head(let head):
            if
                let encoding = head.headers[canonicalForm: "Content-Encoding"].first?.lowercased(),
                let algorithm = CompressionAlgorithm(header: encoding),
                let length = head.headers[canonicalForm: "Content-Length"].first.flatMap({ Int($0) })
            {
                do {
                    try self.initializeDecoder(algorithm: algorithm, length: length)
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
                    try self.stream.inflatePart(input: &part, output: &buffer)
                    self.inflated += buffer.readableBytes

                    if self.limit.exceeded(compressed: compression.contentLength, decompressed: self.inflated) {
                        throw DecompressionError.limit
                    }

                    context.fireChannelRead(self.wrapInboundOut(.body(buffer)))
                } catch let error {
                    context.fireErrorCaught(error)
                    return
                }
            }
        case .end(let headers):
            deflateEnd(&self.stream)
            context.fireChannelRead(self.wrapInboundOut(.end(headers)))
        }
    }

    private func initializeDecoder(algorithm: CompressionAlgorithm, length: Int) throws {
        self.compression = Compression(algorithm: algorithm, contentLength: length)

        self.stream.zalloc = nil
        self.stream.zfree = nil
        self.stream.opaque = nil

        let result = CNIOExtrasZlib_inflateInit2(&self.stream, algorithm.window)
        guard result == Z_OK else {
            throw DecompressionError.initalizationError(result)
        }
    }
}

//extension z_stream {
//    mutating func inflatePart(input: inout ByteBuffer, output: inout ByteBuffer) throws {
//        try input.readWithUnsafeMutableReadableBytes { pointer in
//            self.avail_in = UInt32(pointer.count)
//            self.next_in = CNIOExtrasZlib_voidPtr_to_BytefPtr(pointer.baseAddress!)
//
//            defer {
//                self.avail_in = 0
//                self.next_in = nil
//                self.avail_out = 0
//                self.next_out = nil
//            }
//
//            try self.inflatePart(to: &output)
//
//            return pointer.count - Int(self.avail_in)
//        }
//    }
//
//    private mutating func inflatePart(to buffer: inout ByteBuffer) throws {
//        try buffer.writeWithUnsafeMutableBytes { pointer in
//            self.avail_out = UInt32(pointer.count)
//            self.next_out = CNIOExtrasZlib_voidPtr_to_BytefPtr(pointer.baseAddress!)
//
//            let result = inflate(&self, Z_NO_FLUSH)
//            guard result == Z_OK || result == Z_STREAM_END else {
//                throw NIOHTTPRequestDecompressor.DecompressionError.inflationError(result)
//            }
//
//            return pointer.count - Int(self.avail_out)
//        }
//    }
//}
