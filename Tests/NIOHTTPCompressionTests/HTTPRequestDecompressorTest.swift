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

    func testRatioLimitFiresWithHonestContentLength() throws {
        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(
            NIOHTTPRequestDecompressor(limit: .ratio(10))
        )
        let decompressed = ByteBuffer.of(bytes: Array(repeating: 0, count: 500))
        let compressed = compress(decompressed, "gzip")
        let headers = HTTPHeaders([
            ("Content-Encoding", "gzip"),
            ("Content-Length", "\(compressed.readableBytes)"),
        ])
        try channel.writeInbound(HTTPServerRequestPart.head(.init(
            version: .init(major: 1, minor: 1), method: .POST, uri: "/", headers: headers
        )))
        XCTAssertThrowsError(try channel.writeInbound(HTTPServerRequestPart.body(compressed)))
    }

    func testRatioLimitFiresWithInflatedContentLength() throws {
        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(
            NIOHTTPRequestDecompressor(limit: .ratio(10))
        )
        let decompressed = ByteBuffer.of(bytes: Array(repeating: 0, count: 100_000))
        let compressed = compress(decompressed, "gzip")
        let headers = HTTPHeaders([
            ("Content-Encoding", "gzip"),
            ("Content-Length", "100000"),
        ])
        try channel.writeInbound(HTTPServerRequestPart.head(.init(
            version: .init(major: 1, minor: 1), method: .POST, uri: "/", headers: headers
        )))
        XCTAssertThrowsError(try channel.writeInbound(HTTPServerRequestPart.body(compressed)))
    }

    func testSizeLimitUnaffectedByInflatedContentLength() throws {
        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(
            NIOHTTPRequestDecompressor(limit: .size(50_000))
        )
        let decompressed = ByteBuffer.of(bytes: Array(repeating: 0, count: 100_000))
        let compressed = compress(decompressed, "gzip")
        let headers = HTTPHeaders([
            ("Content-Encoding", "gzip"),
            ("Content-Length", "100000"),
        ])
        try channel.writeInbound(HTTPServerRequestPart.head(.init(
            version: .init(major: 1, minor: 1), method: .POST, uri: "/", headers: headers
        )))
        XCTAssertThrowsError(try channel.writeInbound(HTTPServerRequestPart.body(compressed)))
    }

    func testMultiRequestRatioLimitWithInflatedContentLength() throws {
        let requestCount = 50
        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(
            NIOHTTPRequestDecompressor(limit: .ratio(10))
        )
        let rawPayload = ByteBuffer.of(bytes: Array(repeating: 0, count: 100_000))
        let compressed = compress(rawPayload, "gzip")
        let compressedSize = compressed.readableBytes
        var totalDecompressedBytes = 0
        var ratioLimitFired = false

        for _ in 0..<requestCount {
            let headers = HTTPHeaders([
                ("Content-Encoding", "gzip"),
                ("Content-Length", "100000"),
            ])
            try channel.writeInbound(HTTPServerRequestPart.head(.init(
                version: .init(major: 1, minor: 1), method: .POST, uri: "/", headers: headers
            )))
            do {
                try channel.writeInbound(HTTPServerRequestPart.body(compressed))
            } catch is NIOHTTPDecompression.DecompressionError {
                ratioLimitFired = true
            }
            _ = try? channel.writeInbound(HTTPServerRequestPart.end(nil))
            while let part: HTTPServerRequestPart = try channel.readInbound() {
                if case .body(let buf) = part { totalDecompressedBytes += buf.readableBytes }
            }
        }

        let configuredAllowance = requestCount * compressedSize * 10
        XCTAssertTrue(ratioLimitFired, "Ratio limit must fire — actual amplification far exceeds ratio(10)")
        XCTAssertLessThanOrEqual(
            totalDecompressedBytes, configuredAllowance,
            "Total decompressed bytes (\(totalDecompressedBytes)) must not exceed configured allowance (\(configuredAllowance))"
        )
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

    func testReentrantChannelReadDuringForwardIsSafe() throws {
        let channel = EmbeddedChannel()
        let recorder = Recorder<HTTPServerRequestPart>()

        let reinjected = HTTPServerRequestPart.head(.init(version: .http1_1, method: .GET, uri: "/"))
        try channel.pipeline.syncOperations.addHandler(NIOHTTPRequestDecompressor(limit: .none))
        try channel.pipeline.syncOperations.addHandler(
            ReinjectOnce<HTTPServerRequestPart>(on: .read) { reinjected }
        )
        try channel.pipeline.syncOperations.addHandler(recorder)

        var head = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/")
        head.headers.add(name: "Content-Encoding", value: "gzip")

        XCTAssertNoThrow(try channel.writeInbound(HTTPServerRequestPart.head(head)))
        XCTAssertEqual(recorder.reads.count, 2)
        XCTAssertNoThrow(try channel.finish())
    }

    func testReentrantChannelReadDuringErrorCaughtIsSafe() throws {
        let channel = EmbeddedChannel()
        let recorder = Recorder<HTTPServerRequestPart>()

        let reinjected = HTTPServerRequestPart.head(.init(version: .http1_1, method: .GET, uri: "/"))
        try channel.pipeline.syncOperations.addHandler(NIOHTTPRequestDecompressor(limit: .none))
        try channel.pipeline.syncOperations.addHandler(
            ReinjectOnce<HTTPServerRequestPart>(on: .error) { reinjected }
        )
        try channel.pipeline.syncOperations.addHandler(recorder)

        var head = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/")
        head.headers.add(name: "Content-Encoding", value: "deflate")
        XCTAssertNoThrow(try channel.writeInbound(HTTPServerRequestPart.head(head)))

        // invalid deflate payload
        var badBody = channel.allocator.buffer(capacity: 4)
        badBody.writeBytes([0xff, 0xff, 0xff, 0xff])
        _ = try? channel.writeInbound(HTTPServerRequestPart.body(badBody))

        XCTAssertFalse(recorder.errors.isEmpty)
        XCTAssertTrue(recorder.reads.contains { if case .head = $0 { return true } else { return false } })
        _ = try? channel.finish()
    }

    private final class Recorder<Part>: ChannelInboundHandler {
        typealias InboundIn = Part

        private(set) var reads: [Part] = []
        private(set) var errors: [Error] = []

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            self.reads.append(Self.unwrapInboundIn(data))
            context.fireChannelRead(data)
        }

        func errorCaught(context: ChannelHandlerContext, error: Error) {
            self.errors.append(error)
            context.fireErrorCaught(error)
        }
    }

    private final class ReinjectOnce<Part: Sendable>: ChannelInboundHandler {
        typealias InboundIn = Part

        enum Trigger {
            case read
            case error
        }

        private let trigger: Trigger
        private let reinject: () -> Part
        private var fired = false

        init(on trigger: Trigger, reinject: @escaping () -> Part) {
            self.trigger = trigger
            self.reinject = reinject
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            if self.trigger == .read, !self.fired {
                self.fired = true
                context.channel.pipeline.fireChannelRead(self.reinject())
            }
            context.fireChannelRead(data)
        }

        func errorCaught(context: ChannelHandlerContext, error: Error) {
            if self.trigger == .error, !self.fired {
                self.fired = true
                context.channel.pipeline.fireChannelRead(self.reinject())
            }
            context.fireErrorCaught(error)
        }
    }

    private func compress(_ body: ByteBuffer, _ algorithm: String) -> ByteBuffer {
        var stream = cnioextras_z_stream()

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
            CNIOEXTRAS_Z_DEFAULT_COMPRESSION,
            CNIOEXTRAS_Z_DEFLATED,
            windowBits,
            8,
            CNIOEXTRAS_Z_DEFAULT_STRATEGY
        )
        XCTAssertEqual(CNIOEXTRAS_Z_OK, rc)

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
                let rc = cnioextras_z_deflate(&stream, CNIOEXTRAS_Z_FINISH)
                XCTAssertTrue(rc == CNIOEXTRAS_Z_OK || rc == CNIOEXTRAS_Z_STREAM_END)
                return typedOutputPtr.count - Int(stream.avail_out)
            }

            return typedDataPtr.count - Int(stream.avail_in)
        }

        cnioextras_z_deflateEnd(&stream)

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
