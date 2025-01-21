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

import CNIOExtrasZlib
import NIOCore
import NIOEmbedded
import XCTest

@testable import NIOHTTP1
@testable import NIOHTTPCompression

private let testString =
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."

private final class DecompressedAssert: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let request = self.unwrapInboundIn(data)

        switch request {
        case .body(let buffer):
            let string = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes)
            guard string == testString else {
                context.fireErrorCaught(NIOHTTPDecompression.DecompressionError.inflationError(42))
                return
            }
        default: context.fireChannelRead(data)
        }
    }
}

class HTTPRequestDecompressorTest: XCTestCase {
    func testDecompressionNoLimit() throws {
        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(NIOHTTPRequestDecompressor(limit: .none))
        try channel.pipeline.syncOperations.addHandler(DecompressedAssert())

        let buffer = ByteBuffer.of(string: testString)
        let compressed = compress(buffer, "gzip")

        let headers = HTTPHeaders([("Content-Encoding", "gzip"), ("Content-Length", "\(compressed.readableBytes)")])
        try channel.writeInbound(
            HTTPServerRequestPart.head(
                .init(
                    version: .init(major: 1, minor: 1),
                    method: .POST,
                    uri: "https://nio.swift.org/test",
                    headers: headers
                )
            )
        )

        XCTAssertNoThrow(try channel.writeInbound(HTTPServerRequestPart.body(compressed)))
    }

    func testDecompressionLimitRatio() throws {
        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(NIOHTTPRequestDecompressor(limit: .ratio(10)))
        let decompressed = ByteBuffer.of(bytes: Array(repeating: 0, count: 500))
        let compressed = compress(decompressed, "gzip")
        let headers = HTTPHeaders([("Content-Encoding", "gzip"), ("Content-Length", "\(compressed.readableBytes)")])
        try channel.writeInbound(
            HTTPServerRequestPart.head(
                .init(
                    version: .init(major: 1, minor: 1),
                    method: .POST,
                    uri: "https://nio.swift.org/test",
                    headers: headers
                )
            )
        )

        do {
            try channel.writeInbound(HTTPServerRequestPart.body(compressed))
            XCTFail("writeShouldFail")
        } catch let error as NIOHTTPDecompression.DecompressionError {
            switch error {
            case .limit:
                // ok
                break
            default:
                XCTFail("Unexptected error: \(error)")
            }
        }
    }

    func testDecompressionLimitSize() throws {
        let channel = EmbeddedChannel()
        let decompressed = ByteBuffer.of(bytes: Array(repeating: 0, count: 200))
        let compressed = compress(decompressed, "gzip")
        try channel.pipeline.syncOperations.addHandler(
            NIOHTTPRequestDecompressor(limit: .size(decompressed.readableBytes - 1))
        )
        let headers = HTTPHeaders([("Content-Encoding", "gzip"), ("Content-Length", "\(compressed.readableBytes)")])
        try channel.writeInbound(
            HTTPServerRequestPart.head(
                .init(
                    version: .init(major: 1, minor: 1),
                    method: .POST,
                    uri: "https://nio.swift.org/test",
                    headers: headers
                )
            )
        )

        do {
            try channel.writeInbound(HTTPServerRequestPart.body(compressed))
            XCTFail("writeInbound should fail")
        } catch let error as NIOHTTPDecompression.DecompressionError {
            switch error {
            case .limit:
                // ok
                break
            default:
                XCTFail("Unexptected error: \(error)")
            }
        }
    }

    func testDecompression() throws {
        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(NIOHTTPRequestDecompressor(limit: .none))

        let body = Array(repeating: testString, count: 1000).joined()
        let algorithms: [(actual: String, announced: String)?] = [
            nil,
            (actual: "gzip", announced: "gzip"),
            (actual: "deflate", announced: "deflate"),
            (actual: "gzip", announced: "deflate"),
            (actual: "deflate", announced: "gzip"),
        ]

        for algorithm in algorithms {
            let compressed: ByteBuffer
            var headers = HTTPHeaders()
            if let algorithm = algorithm {
                headers.add(name: "Content-Encoding", value: algorithm.announced)
                compressed = compress(ByteBuffer.of(string: body), algorithm.actual)
            } else {
                compressed = ByteBuffer.of(string: body)
            }
            headers.add(name: "Content-Length", value: "\(compressed.readableBytes)")

            XCTAssertNoThrow(
                try channel.writeInbound(
                    HTTPServerRequestPart.head(
                        .init(
                            version: .init(major: 1, minor: 1),
                            method: .POST,
                            uri: "https://nio.swift.org/test",
                            headers: headers
                        )
                    )
                )
            )

            XCTAssertNoThrow(try channel.writeInbound(HTTPServerRequestPart.body(compressed)))
            XCTAssertNoThrow(try channel.writeInbound(HTTPServerRequestPart.end(nil)))
        }
    }

    func testDecompressionTrailingData() throws {
        // Valid compressed data with some trailing garbage
        let compressed = ByteBuffer(bytes: [120, 156, 99, 0, 0, 0, 1, 0, 1] + [1, 2, 3])

        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(NIOHTTPRequestDecompressor(limit: .none))
        let headers = HTTPHeaders([("Content-Encoding", "deflate"), ("Content-Length", "\(compressed.readableBytes)")])
        try channel.writeInbound(
            HTTPServerRequestPart.head(
                .init(
                    version: .init(major: 1, minor: 1),
                    method: .POST,
                    uri: "https://nio.swift.org/test",
                    headers: headers
                )
            )
        )

        XCTAssertThrowsError(try channel.writeInbound(HTTPServerRequestPart.body(compressed)))
    }

    func testDecompressionTruncatedInput() throws {
        // Truncated compressed data
        let compressed = ByteBuffer(bytes: [120, 156, 99, 0])

        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(NIOHTTPRequestDecompressor(limit: .none))
        let headers = HTTPHeaders([("Content-Encoding", "deflate"), ("Content-Length", "\(compressed.readableBytes)")])
        try channel.writeInbound(
            HTTPServerRequestPart.head(
                .init(
                    version: .init(major: 1, minor: 1),
                    method: .POST,
                    uri: "https://nio.swift.org/test",
                    headers: headers
                )
            )
        )

        XCTAssertNoThrow(try channel.writeInbound(HTTPServerRequestPart.body(compressed)))
        XCTAssertThrowsError(try channel.writeInbound(HTTPServerRequestPart.end(nil)))
    }

    private func compress(_ body: ByteBuffer, _ algorithm: String) -> ByteBuffer {
        var stream = z_stream()

        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil

        var buffer = ByteBufferAllocator().buffer(capacity: 1000)

        let windowBits: Int32
        switch algorithm {
        case "deflate":
            windowBits = 15
        case "gzip":
            windowBits = 16 + 15
        default:
            XCTFail("Unsupported algorithm: \(algorithm)")
            return buffer
        }

        let rc = CNIOExtrasZlib_deflateInit2(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            windowBits,
            8,
            Z_DEFAULT_STRATEGY
        )
        XCTAssertEqual(Z_OK, rc)

        defer {
            stream.avail_in = 0
            stream.next_in = nil
            stream.avail_out = 0
            stream.next_out = nil
        }

        var body = body

        body.readWithUnsafeMutableReadableBytes { dataPtr in
            let typedPtr = dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let typedDataPtr = UnsafeMutableBufferPointer(
                start: typedPtr,
                count: dataPtr.count
            )

            stream.avail_in = UInt32(typedDataPtr.count)
            stream.next_in = typedDataPtr.baseAddress!

            buffer.writeWithUnsafeMutableBytes(minimumWritableBytes: 0) { outputPtr in
                let typedOutputPtr = UnsafeMutableBufferPointer(
                    start: outputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    count: outputPtr.count
                )
                stream.avail_out = UInt32(typedOutputPtr.count)
                stream.next_out = typedOutputPtr.baseAddress!
                let rc = deflate(&stream, Z_FINISH)
                XCTAssertTrue(rc == Z_OK || rc == Z_STREAM_END)
                return typedOutputPtr.count - Int(stream.avail_out)
            }

            return typedDataPtr.count - Int(stream.avail_in)
        }

        deflateEnd(&stream)

        return buffer
    }
}

extension ByteBuffer {
    fileprivate static func of(string: String) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: string.count)
        buffer.writeString(string)
        return buffer
    }

    fileprivate static func of(bytes: [UInt8]) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        return buffer
    }
}
