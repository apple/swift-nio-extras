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

import XCTest
import CNIOExtrasZlib
@testable import NIO
@testable import NIOHTTP1
@testable import NIOHTTPCompression

class HTTPResponseDecompressorTest: XCTestCase {
    func testDecompressionNoLimit() throws {
        let channel = EmbeddedChannel()
        try channel.pipeline.addHandler(NIOHTTPResponseDecompressor(limit: .none)).wait()

        let headers = HTTPHeaders([("Content-Encoding", "deflate"), ("Content-Length", "13")])
        try channel.writeInbound(HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers)))

        let body = ByteBuffer.of(bytes: [120, 156, 75, 76, 28, 5, 200, 0, 0, 248, 66, 103, 17])
        XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.body(body)))
    }

    func testDecompressionLimitRatio() throws {
        let channel = EmbeddedChannel()
        try channel.pipeline.addHandler(NIOHTTPResponseDecompressor(limit: .ratio(10))).wait()

        let headersArray = [
            HTTPHeaders([("Content-Encoding", "deflate"), ("Content-Length", "13")]),
            HTTPHeaders([("Content-Encoding", "deflate")])
        ]
        
        for headers in headersArray {
            try channel.writeInbound(HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers)))

            let body = ByteBuffer.of(bytes: [120, 156, 75, 76, 28, 5, 200, 0, 0, 248, 66, 103, 17])
            XCTAssertThrowsError(try channel.writeInbound(HTTPClientResponsePart.body(body))) { error in
                XCTAssertEqual(error as? NIOHTTPDecompression.DecompressionError, .limit)
            }
        }
    }

    func testDecompressionLimitSize() throws {
        let channel = EmbeddedChannel()
        try channel.pipeline.addHandler(NIOHTTPResponseDecompressor(limit: .size(15))).wait()

        let headersArray = [
            HTTPHeaders([("Content-Encoding", "deflate"), ("Content-Length", "13")]),
            HTTPHeaders([("Content-Encoding", "deflate")])
        ]
        
        for headers in headersArray {
            try channel.writeInbound(HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers)))

            let body = ByteBuffer.of(bytes: [120, 156, 75, 76, 28, 5, 200, 0, 0, 248, 66, 103, 17])
            XCTAssertThrowsError(try channel.writeInbound(HTTPClientResponsePart.body(body))) { error in
                XCTAssertEqual(error as? NIOHTTPDecompression.DecompressionError, .limit)
            }
        }
    }

    func testDecompression() throws {
        let channel = EmbeddedChannel()
        try channel.pipeline.addHandler(NIOHTTPResponseDecompressor(limit: .none)).wait()

        var body = ""
        for _ in 1...1000 {
            body += "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
        }

        for algorithm in [nil, "gzip", "deflate"] {
            let compressed: ByteBuffer
            var headers = HTTPHeaders()
            if let algorithm = algorithm {
                headers.add(name: "Content-Encoding", value: algorithm)
                compressed = compress(ByteBuffer.of(string: body), algorithm)
            } else {
                compressed = ByteBuffer.of(string: body)
            }
            headers.add(name: "Content-Length", value: "\(compressed.readableBytes)")

            XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers))))
            XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.body(compressed)))
        }

        XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.end(nil)))
    }
    
    func testDecompressionWithoutContentLength() throws {
        let channel = EmbeddedChannel()
        try channel.pipeline.addHandler(NIOHTTPResponseDecompressor(limit: .none)).wait()

        let expectedBody = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."

        for algorithm in [nil, "gzip", "deflate"] {
            let compressed: ByteBuffer
            var headers = HTTPHeaders()
            if let algorithm = algorithm {
                headers.add(name: "Content-Encoding", value: algorithm)
                compressed = compress(ByteBuffer.of(string: expectedBody), algorithm)
            } else {
                compressed = ByteBuffer.of(string: expectedBody)
            }

            XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.head(.init(version: .init(major: 1, minor: 1), status: .ok, headers: headers))))
            XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.body(compressed)))
            
            XCTAssertNoThrow(try channel.readInbound(as: Any.self))
            
            
            if case .body(let buffer) = try channel.readInbound(as: HTTPClientResponsePart.self) {
                let bodyData = Data(buffer.readableBytesView)
                guard let bodyString = String(data: bodyData, encoding: .utf8) else {
                    XCTFail("Impossible to decode string decompressed from algorithm: \(algorithm ?? "non-compressed")")
                    return
                }
                
                XCTAssertEqual(bodyString, expectedBody, "Decompressed string not equal to expected result from algorithm \(algorithm ?? "non-compressed")")
                
            } else {
                XCTFail("Unexpected response part")
            }
        }

        XCTAssertNoThrow(try channel.writeInbound(HTTPClientResponsePart.end(nil)))
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

        let rc = CNIOExtrasZlib_deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, windowBits, 8, Z_DEFAULT_STRATEGY)
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
            let typedDataPtr = UnsafeMutableBufferPointer(start: typedPtr,
                                                          count: dataPtr.count)

            stream.avail_in = UInt32(typedDataPtr.count)
            stream.next_in = typedDataPtr.baseAddress!

            buffer.writeWithUnsafeMutableBytes(minimumWritableBytes: 0) { outputPtr in
                let typedOutputPtr = UnsafeMutableBufferPointer(start: outputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                                                                count: outputPtr.count)
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
