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
import NIOEmbedded
import XCTest

@testable import NIOCore
@testable import NIOHTTP1
@testable import NIOHTTPCompression

class HTTPResponseDecompressorTest: XCTestCase {
    func testDecompressionNoLimit() throws {
        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .none))

        let headers = HTTPHeaders([("Content-Encoding", "deflate"), ("Content-Length", "13")])
        try channel.writeInbound(
            HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers))
        )

        let body = ByteBuffer.of(bytes: [120, 156, 75, 76, 28, 5, 200, 0, 0, 248, 66, 103, 17])
        XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.body(body)))
    }

    func testDecompressionLimitSizeWithContentLenghtHeaderSucceeds() {
        let channel = EmbeddedChannel()
        XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .size(272))))

        let headers = HTTPHeaders([("Content-Encoding", "deflate"), ("Content-Length", "13")])

        XCTAssertNoThrow(
            try channel.writeInbound(
                HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers))
            )
        )

        // this compressed payload is 272 bytes long uncompressed
        let body = ByteBuffer.of(bytes: [120, 156, 75, 76, 28, 5, 200, 0, 0, 248, 66, 103, 17])
        XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.body(body)))
    }

    func testDecompressionLimitSizeWithContentLenghtHeaderFails() {
        let channel = EmbeddedChannel()
        XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .size(271))))

        let headers = HTTPHeaders([("Content-Encoding", "deflate"), ("Content-Length", "13")])

        XCTAssertNoThrow(
            try channel.writeInbound(
                HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers))
            )
        )

        // this compressed payload is 272 bytes long uncompressed
        let body = ByteBuffer.of(bytes: [120, 156, 75, 76, 28, 5, 200, 0, 0, 248, 66, 103, 17])
        XCTAssertThrowsError(try channel.writeInbound(HTTPClientResponsePart.body(body))) { error in
            XCTAssertEqual(error as? NIOHTTPDecompression.DecompressionError, .limit)
        }
    }

    func testDecompressionLimitSizeWithoutContentLenghtHeaderSucceeds() {
        let channel = EmbeddedChannel()
        XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .size(272))))

        let headers = HTTPHeaders([("Content-Encoding", "deflate")])

        XCTAssertNoThrow(
            try channel.writeInbound(
                HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers))
            )
        )

        // this compressed payload is 272 bytes long uncompressed
        let body = ByteBuffer.of(bytes: [120, 156, 75, 76, 28, 5, 200, 0, 0, 248, 66, 103, 17])
        XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.body(body)))
    }

    func testDecompressionLimitSizeWithoutContentLenghtHeaderFails() {
        let channel = EmbeddedChannel()
        XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .size(271))))

        let headers = HTTPHeaders([("Content-Encoding", "deflate")])

        XCTAssertNoThrow(
            try channel.writeInbound(
                HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers))
            )
        )

        // this compressed payload is 272 bytes long uncompressed
        let body = ByteBuffer.of(bytes: [120, 156, 75, 76, 28, 5, 200, 0, 0, 248, 66, 103, 17])
        XCTAssertThrowsError(try channel.writeInbound(HTTPClientResponsePart.body(body))) { error in
            XCTAssertEqual(error as? NIOHTTPDecompression.DecompressionError, .limit)
        }
    }

    func testDecompressionLimitRatioWithContentLenghtHeaderSucceeds() {
        let channel = EmbeddedChannel()
        XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .ratio(21))))

        let headers = HTTPHeaders([("Content-Encoding", "deflate"), ("Content-Length", "13")])

        XCTAssertNoThrow(
            try channel.writeInbound(
                HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers))
            )
        )

        // this compressed payload is 272 bytes long uncompressed
        let body = ByteBuffer.of(bytes: [120, 156, 75, 76, 28, 5, 200, 0, 0, 248, 66, 103, 17])
        XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.body(body)))
    }

    func testDecompressionLimitRatioWithContentLenghtHeaderFails() {
        let channel = EmbeddedChannel()
        XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .ratio(20))))

        let headers = HTTPHeaders([("Content-Encoding", "deflate"), ("Content-Length", "13")])

        XCTAssertNoThrow(
            try channel.writeInbound(
                HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers))
            )
        )

        // this compressed payload is 272 bytes long uncompressed
        let body = ByteBuffer.of(bytes: [120, 156, 75, 76, 28, 5, 200, 0, 0, 248, 66, 103, 17])
        XCTAssertThrowsError(try channel.writeInbound(HTTPClientResponsePart.body(body))) { error in
            XCTAssertEqual(error as? NIOHTTPDecompression.DecompressionError, .limit)
        }
    }

    func testDecompressionLimitRatioWithoutContentLenghtHeaderSucceeds() {
        let channel = EmbeddedChannel()
        XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .ratio(21))))

        let headers = HTTPHeaders([("Content-Encoding", "deflate")])

        XCTAssertNoThrow(
            try channel.writeInbound(
                HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers))
            )
        )

        // this compressed payload is 272 bytes long uncompressed
        let body = ByteBuffer.of(bytes: [120, 156, 75, 76, 28, 5, 200, 0, 0, 248, 66, 103, 17])
        XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.body(body)))
    }

    func testDecompressionLimitRatioWithoutContentLenghtHeaderFails() {
        let channel = EmbeddedChannel()
        XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .ratio(20))))

        let headers = HTTPHeaders([("Content-Encoding", "deflate")])

        XCTAssertNoThrow(
            try channel.writeInbound(
                HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers))
            )
        )

        // this compressed payload is 272 bytes long uncompressed
        let body = ByteBuffer.of(bytes: [120, 156, 75, 76, 28, 5, 200, 0, 0, 248, 66, 103, 17])
        XCTAssertThrowsError(try channel.writeInbound(HTTPClientResponsePart.body(body))) { error in
            XCTAssertEqual(error as? NIOHTTPDecompression.DecompressionError, .limit)
        }
    }

    func testDecompressionMultipleWriteWithLimit() {
        let channel = EmbeddedChannel()
        XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .size(272))))

        let headers = HTTPHeaders([("Content-Encoding", "deflate")])
        // this compressed payload is 272 bytes long uncompressed
        let body = ByteBuffer.of(bytes: [120, 156, 75, 76, 28, 5, 200, 0, 0, 248, 66, 103, 17])

        for i in 0..<3 {
            XCTAssertNoThrow(
                try channel.writeInbound(
                    HTTPClientResponsePart.head(
                        .init(version: .init(major: 1, minor: 1), status: .ok, headers: headers)
                    )
                ),
                "\(i)"
            )
            XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.body(body)), "\(i)")
            XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.end(nil)), "\(i)")
        }
    }

    func testDecompression() {
        let channel = EmbeddedChannel()
        XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .none)))

        var body = ""
        for _ in 1...1000 {
            body +=
                "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
        }
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
                    HTTPClientResponsePart.head(
                        .init(version: .init(major: 1, minor: 1), status: .ok, headers: headers)
                    )
                )
            )
            XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.body(compressed)))
            XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.end(nil)))

            var head: HTTPClientResponsePart?
            XCTAssertNoThrow(head = try channel.readInbound(as: HTTPClientResponsePart.self))
            XCTAssertEqual(
                head,
                HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers))
            )

            // the response is chunked
            var next: HTTPClientResponsePart?
            XCTAssertNoThrow(next = try channel.readInbound(as: HTTPClientResponsePart.self))
            var buffer = ByteBuffer.of(bytes: [])
            while let part = next {
                switch part {
                case .head:
                    XCTFail("Unexpected head http part")
                case .body(var input):
                    buffer.writeBuffer(&input)
                case .end:
                    break
                }
                XCTAssertNoThrow(next = try channel.readInbound(as: HTTPClientResponsePart.self))
            }
            XCTAssertEqual(buffer, ByteBuffer.of(string: body))
        }
    }

    func testDecompressionWithoutContentLength() {
        let channel = EmbeddedChannel()
        XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .none)))

        var body = ""
        for _ in 1...1000 {
            body +=
                "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
        }

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

            XCTAssertNoThrow(
                try channel.writeInbound(
                    HTTPClientResponsePart.head(
                        .init(version: .init(major: 1, minor: 1), status: .ok, headers: headers)
                    )
                )
            )
            XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.body(compressed)))
            XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.end(nil)))

            var head: HTTPClientResponsePart?
            XCTAssertNoThrow(head = try channel.readInbound(as: HTTPClientResponsePart.self))
            XCTAssertEqual(
                head,
                HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers))
            )

            // the response is chunked
            var next: HTTPClientResponsePart?
            XCTAssertNoThrow(next = try channel.readInbound(as: HTTPClientResponsePart.self))
            var buffer = ByteBuffer.of(bytes: [])
            while let part = next {
                switch part {
                case .head:
                    XCTFail("Unexpected head http part")
                case .body(var input):
                    buffer.writeBuffer(&input)
                case .end:
                    break
                }
                XCTAssertNoThrow(next = try channel.readInbound(as: HTTPClientResponsePart.self))
            }

            XCTAssertEqual(buffer, ByteBuffer.of(string: body))
        }

        XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.end(nil)))
    }

    func testDecompressionTrailingData() throws {
        // Valid compressed data with some trailing garbage
        let compressed = ByteBuffer(bytes: [120, 156, 99, 0, 0, 0, 1, 0, 1] + [1, 2, 3])

        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .none))
        let headers = HTTPHeaders([("Content-Encoding", "deflate"), ("Content-Length", "\(compressed.readableBytes)")])
        try channel.writeInbound(
            HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers))
        )

        XCTAssertThrowsError(try channel.writeInbound(HTTPClientResponsePart.body(compressed)))
    }

    func testDecompressionTruncatedInput() throws {
        // Truncated compressed data
        let compressed = ByteBuffer(bytes: [120, 156, 99, 0])

        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .none))
        let headers = HTTPHeaders([("Content-Encoding", "deflate"), ("Content-Length", "\(compressed.readableBytes)")])
        try channel.writeInbound(
            HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers))
        )

        XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.body(compressed)))
        XCTAssertThrowsError(try channel.writeInbound(HTTPClientResponsePart.end(nil)))
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
