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
import NIO
import NIOHTTP1
@testable import NIOHTTPCompression

struct PromiseArray {
    var promises: [EventLoopPromise<Void>]
    let eventLoop: EventLoop
    
    init(on eventLoop: EventLoop) {
        self.promises = []
        self.eventLoop = eventLoop
    }
    
    mutating func makePromise() -> EventLoopPromise<Void> {
        let promise: EventLoopPromise<Void> = eventLoop.makePromise()
        self.promises.append(promise)
        return promise
    }
    
    func waitUntilComplete() throws {
        let resultFutures = promises.map { $0.futureResult }
        _ = try EventLoopFuture.whenAllComplete(resultFutures, on: eventLoop).wait()
    }
}

private extension ByteBuffer {
    @discardableResult
    mutating func withUnsafeMutableReadableUInt8Bytes<T>(_ body: (UnsafeMutableBufferPointer<UInt8>) throws -> T) rethrows -> T {
        return try self.withUnsafeMutableReadableBytes { (ptr: UnsafeMutableRawBufferPointer) -> T in
            let baseInputPointer = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self)
            let inputBufferPointer = UnsafeMutableBufferPointer(start: baseInputPointer, count: ptr.count)
            return try body(inputBufferPointer)
        }
    }

    @discardableResult
    mutating func writeWithUnsafeMutableUInt8Bytes(_ body: (UnsafeMutableBufferPointer<UInt8>) throws -> Int) rethrows -> Int {
        return try self.writeWithUnsafeMutableBytes(minimumWritableBytes: 0) { (ptr: UnsafeMutableRawBufferPointer) -> Int in
            let baseInputPointer = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self)
            let inputBufferPointer = UnsafeMutableBufferPointer(start: baseInputPointer, count: ptr.count)
            return try body(inputBufferPointer)
        }
    }
}

private extension z_stream {
    static func decompressDeflate(compressedBytes: inout ByteBuffer, outputBuffer: inout ByteBuffer) {
        decompress(compressedBytes: &compressedBytes, outputBuffer: &outputBuffer, windowSize: 15)
    }

    static func decompressGzip(compressedBytes: inout ByteBuffer, outputBuffer: inout ByteBuffer) {
        decompress(compressedBytes: &compressedBytes, outputBuffer: &outputBuffer, windowSize: 16 + 15)
    }

    private static func decompress(compressedBytes: inout ByteBuffer, outputBuffer: inout ByteBuffer, windowSize: Int32) {
        compressedBytes.withUnsafeMutableReadableUInt8Bytes { inputPointer in
            outputBuffer.writeWithUnsafeMutableUInt8Bytes { outputPointer -> Int in
                var stream = z_stream()

                // zlib requires we initialize next_in, avail_in, zalloc, zfree and opaque before calling inflateInit2.
                stream.next_in = inputPointer.baseAddress!
                stream.avail_in = UInt32(inputPointer.count)
                stream.next_out = outputPointer.baseAddress!
                stream.avail_out = UInt32(outputPointer.count)
                stream.zalloc = nil
                stream.zfree = nil
                stream.opaque = nil

                var rc = CNIOExtrasZlib_inflateInit2(&stream, windowSize)
                precondition(rc == Z_OK)

                rc = inflate(&stream, Z_FINISH)
                XCTAssertEqual(rc, Z_STREAM_END)
                XCTAssertEqual(stream.avail_in, 0)

                rc = inflateEnd(&stream)
                XCTAssertEqual(rc, Z_OK)

                return outputPointer.count - Int(stream.avail_out)
            }
        }
    }
}

class HTTPRequestCompressorTest: XCTestCase {
    
    func compressionChannel(_ compression: HTTPCompression.CompressionAlgorithm = .gzip) throws -> EmbeddedChannel {
        let channel = EmbeddedChannel()
        //XCTAssertNoThrow(try channel.pipeline.addHandler(HTTPRequestEncoder(), name: "encoder").wait())
        XCTAssertNoThrow(try channel.pipeline.addHandler(HTTPRequestCompressor(encoding: compression), name: "compressor").wait())
        return channel
    }
    
    func write(body: [ByteBuffer], to channel: EmbeddedChannel) throws {
        let requestHead = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "/")
        try write(head: requestHead, body: body, to: channel)
    }
    
    func write(head: HTTPRequestHead, body: [ByteBuffer], to channel: EmbeddedChannel) throws {
        var promiseArray = PromiseArray(on: channel.eventLoop)
        channel.pipeline.write(NIOAny(HTTPClientRequestPart.head(head)), promise: promiseArray.makePromise())

        for bodyChunk in body {
            channel.pipeline.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(bodyChunk))), promise: promiseArray.makePromise())
        }
        channel.pipeline.write(NIOAny(HTTPClientRequestPart.end(nil)), promise: promiseArray.makePromise())
        channel.pipeline.flush()
        
        try promiseArray.waitUntilComplete()
    }
    
    func writeWithIntermittantFlush(body: [ByteBuffer], to channel: EmbeddedChannel) throws {
        let requestHead = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "/")
        try writeWithIntermittantFlush(head: requestHead, body: body, to: channel)
    }
    
    func writeWithIntermittantFlush(head: HTTPRequestHead, body: [ByteBuffer], to channel: EmbeddedChannel) throws {
        var promiseArray = PromiseArray(on: channel.eventLoop)
        var count = 3
        channel.pipeline.write(NIOAny(HTTPClientRequestPart.head(head)), promise: promiseArray.makePromise())

        for bodyChunk in body {
            channel.pipeline.write(
                NIOAny(HTTPClientRequestPart.body(.byteBuffer(bodyChunk))),
                promise: promiseArray.makePromise()
            )
            count -= 1
            if count == 0 {
                channel.pipeline.flush()
                count = 3
            }
        }
        channel.pipeline.write(NIOAny(HTTPClientRequestPart.end(nil)), promise: promiseArray.makePromise())
        channel.pipeline.flush()
        
        try promiseArray.waitUntilComplete()
    }

    func read(from channel: EmbeddedChannel) throws -> ByteBuffer {
        var byteBuffer = channel.allocator.buffer(capacity: 0)
        channel.pipeline.read()
        loop: while let requestPart: HTTPClientRequestPart = try channel.readOutbound() {
            switch requestPart {
            case .head(_):
                break
            case .body(let data):
                if case .byteBuffer(var buffer) = data {
                    byteBuffer.writeBuffer(&buffer)
                }
            case .end:
                break loop
            }
        }
        return byteBuffer
    }
    
    func readVerifyPart(from channel: EmbeddedChannel, verify: (HTTPClientRequestPart)->()) throws {
        channel.pipeline.read()
        loop: while let requestPart: HTTPClientRequestPart = try channel.readOutbound() {
            verify(requestPart)
        }
    }
    
    func testGzipContentEncoding() throws {
        let channel = try compressionChannel()
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString("Test")
        
        _ = try write(body: [buffer], to: channel)
        try readVerifyPart(from: channel) { part in
            if case .head(let head) = part {
                XCTAssertEqual(head.headers["Content-Encoding"].first, "gzip")
            }
        }
    }
    
    func testDeflateContentEncoding() throws {
        let channel = try compressionChannel(.deflate)
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString("Test")
        
        _ = try write(body: [buffer], to: channel)
        try readVerifyPart(from: channel) { part in
            if case .head(let head) = part {
                XCTAssertEqual(head.headers["Content-Encoding"].first, "deflate")
            }
        }
    }
    
    func testOneBuffer() throws {
        let channel = try compressionChannel()
        var buffer = ByteBufferAllocator().buffer(capacity: 1024 * Int.bitWidth / 8)
        for _ in 0..<1024 {
            buffer.writeInteger(Int.random(in: Int.min...Int.max))
        }
        
        _ = try write(body: [buffer], to: channel)
        var result = try read(from: channel)
        var uncompressedBuffer = ByteBufferAllocator().buffer(capacity: buffer.readableBytes)
        z_stream.decompressGzip(compressedBytes: &result, outputBuffer: &uncompressedBuffer)
        
        XCTAssertEqual(buffer, uncompressedBuffer)
    }

    func testMultipleBuffers() throws {
        let channel = try compressionChannel()
        var buffers: [ByteBuffer] = []
        var buffersConcat = ByteBufferAllocator().buffer(capacity: 16 * 1024 * Int.bitWidth / 8)
        for _ in 0..<16 {
            var buffer = ByteBufferAllocator().buffer(capacity: 1024 * Int.bitWidth / 8)
            for _ in 0..<1024 {
                buffer.writeInteger(Int.random(in: Int.min...Int.max))
            }
            buffers.append(buffer)
            buffersConcat.writeBuffer(&buffer)
        }

        try write(body: buffers, to: channel)
        var result = try read(from: channel)
        var uncompressedBuffer = ByteBufferAllocator().buffer(capacity: buffersConcat.readableBytes)
        z_stream.decompressGzip(compressedBytes: &result, outputBuffer: &uncompressedBuffer)
        
        XCTAssertEqual(buffersConcat, uncompressedBuffer)
    }
    
    func testMultipleBuffersDeflate() throws {
        let channel = try compressionChannel(.deflate)
        var buffers: [ByteBuffer] = []
        var buffersConcat = ByteBufferAllocator().buffer(capacity: 16 * 1024 * Int.bitWidth / 8)
        for _ in 0..<16 {
            var buffer = ByteBufferAllocator().buffer(capacity: 1024 * Int.bitWidth / 8)
            for _ in 0..<1024 {
                buffer.writeInteger(Int.random(in: Int.min...Int.max))
            }
            buffers.append(buffer)
            buffersConcat.writeBuffer(&buffer)
        }

        try write(body: buffers, to: channel)
        var result = try read(from: channel)
        var uncompressedBuffer = ByteBufferAllocator().buffer(capacity: buffersConcat.readableBytes)
        z_stream.decompressDeflate(compressedBytes: &result, outputBuffer: &uncompressedBuffer)
        
        XCTAssertEqual(buffersConcat, uncompressedBuffer)
    }
    
    func testMultipleBuffersWithFlushes() throws {
        let channel = try compressionChannel()
        var buffers: [ByteBuffer] = []
        var buffersConcat = ByteBufferAllocator().buffer(capacity: 16 * 1024 * Int.bitWidth / 8)
        for _ in 0..<16 {
            var buffer = ByteBufferAllocator().buffer(capacity: 1024 * Int.bitWidth / 8)
            for _ in 0..<1024 {
                buffer.writeInteger(Int.random(in: Int.min...Int.max))
            }
            buffers.append(buffer)
            buffersConcat.writeBuffer(&buffer)
        }

        try writeWithIntermittantFlush(body: buffers, to: channel)
        var result = try read(from: channel)
        var uncompressedBuffer = ByteBufferAllocator().buffer(capacity: buffersConcat.readableBytes)
        z_stream.decompressGzip(compressedBytes: &result, outputBuffer: &uncompressedBuffer)
        
        XCTAssertEqual(buffersConcat, uncompressedBuffer)
    }

    func testFlushAfterHead() throws {
        let channel = try compressionChannel()
        var buffer = ByteBufferAllocator().buffer(capacity: 1024 * Int.bitWidth / 8)
        for _ in 0..<1024 {
            buffer.writeInteger(Int.random(in: Int.min...Int.max))
        }
        
        let requestHead = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "/")
        var promiseArray = PromiseArray(on: channel.eventLoop)
        channel.pipeline.write(NIOAny(HTTPClientRequestPart.head(requestHead)), promise: promiseArray.makePromise())
        channel.pipeline.flush()
        channel.pipeline.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(buffer))), promise: promiseArray.makePromise())
        channel.pipeline.write(NIOAny(HTTPClientRequestPart.end(nil)), promise: promiseArray.makePromise())
        channel.pipeline.flush()
        try promiseArray.waitUntilComplete()

        var result = try read(from: channel)
        var uncompressedBuffer = ByteBufferAllocator().buffer(capacity: buffer.readableBytes)
        z_stream.decompressGzip(compressedBytes: &result, outputBuffer: &uncompressedBuffer)
        
        XCTAssertEqual(buffer, uncompressedBuffer)
    }
    
    func testFlushBeforeEnd() throws {
        let channel = try compressionChannel()
        var buffer = ByteBufferAllocator().buffer(capacity: 1024 * Int.bitWidth / 8)
        for _ in 0..<1024 {
            buffer.writeInteger(Int.random(in: Int.min...Int.max))
        }
        
        let requestHead = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "/")
        var promiseArray = PromiseArray(on: channel.eventLoop)
        channel.pipeline.write(NIOAny(HTTPClientRequestPart.head(requestHead)), promise: promiseArray.makePromise())
        channel.pipeline.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(buffer))), promise: promiseArray.makePromise())
        channel.pipeline.flush()
        channel.pipeline.write(NIOAny(HTTPClientRequestPart.end(nil)), promise: promiseArray.makePromise())
        channel.pipeline.flush()
        try promiseArray.waitUntilComplete()

        var result = try read(from: channel)
        var uncompressedBuffer = ByteBufferAllocator().buffer(capacity: buffer.readableBytes)
        z_stream.decompressGzip(compressedBytes: &result, outputBuffer: &uncompressedBuffer)
        
        XCTAssertEqual(buffer, uncompressedBuffer)
    }
    
    func testDoubleFlush() throws {
        let channel = try compressionChannel()
        var buffer = ByteBufferAllocator().buffer(capacity: 1024 * Int.bitWidth / 8)
        for _ in 0..<1024 {
            buffer.writeInteger(Int.random(in: Int.min...Int.max))
        }
        
        let requestHead = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "/")
        var promiseArray = PromiseArray(on: channel.eventLoop)
        channel.pipeline.write(NIOAny(HTTPClientRequestPart.head(requestHead)), promise: promiseArray.makePromise())
        channel.pipeline.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(buffer))), promise: promiseArray.makePromise())
        channel.pipeline.flush()
        channel.pipeline.flush()
        channel.pipeline.write(NIOAny(HTTPClientRequestPart.end(nil)), promise: promiseArray.makePromise())
        channel.pipeline.flush()
        try promiseArray.waitUntilComplete()

        var result = try read(from: channel)
        var uncompressedBuffer = ByteBufferAllocator().buffer(capacity: buffer.readableBytes)
        z_stream.decompressGzip(compressedBytes: &result, outputBuffer: &uncompressedBuffer)
        
        XCTAssertEqual(buffer, uncompressedBuffer)
    }
    
    func testNoBody() throws {
        let channel = try compressionChannel()
        
        let requestHead = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "/")
        var promiseArray = PromiseArray(on: channel.eventLoop)
        channel.pipeline.write(NIOAny(HTTPClientRequestPart.head(requestHead)), promise: promiseArray.makePromise())
        channel.pipeline.write(NIOAny(HTTPClientRequestPart.end(nil)), promise: promiseArray.makePromise())
        channel.pipeline.flush()
        try promiseArray.waitUntilComplete()

        try readVerifyPart(from: channel) { part in
            switch part {
            case .head(let head):
                XCTAssertNil(head.headers["Content-Encoding"].first)
            case.body:
                XCTFail("Shouldn't return a body")
            case .end:
                break
            }
        }
    }
}

