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
import NIOConcurrencyHelpers
@testable import NIOHTTPCompression

private class PromiseOrderer {
    private var promiseArray: Array<EventLoopPromise<Void>>
    private let eventLoop: EventLoop

    internal init(eventLoop: EventLoop) {
        promiseArray = Array()
        self.eventLoop = eventLoop
    }

    func makePromise(file: StaticString = #file, line: UInt = #line) -> EventLoopPromise<Void> {
        let promise = eventLoop.makePromise(of: Void.self, file: (file), line: line)
        appendPromise(promise)
        return promise
    }

    private func appendPromise(_ promise: EventLoopPromise<Void>) {
        let thisPromiseIndex = promiseArray.count
        promiseArray.append(promise)

        promise.futureResult.whenComplete { (_: Result<Void, Error>) in
            let priorFutures = self.promiseArray[0..<thisPromiseIndex]
            let subsequentFutures = self.promiseArray[(thisPromiseIndex + 1)...]
            let allPriorFuturesFired = priorFutures.map { $0.futureResult.isFulfilled }.allSatisfy { $0 }
            let allSubsequentFuturesUnfired = subsequentFutures.map { $0.futureResult.isFulfilled }.allSatisfy { !$0 }

            XCTAssertTrue(allPriorFuturesFired)
            XCTAssertTrue(allSubsequentFuturesUnfired)
        }
    }

    func waitUntilComplete() throws {
        guard let promise = promiseArray.last else { return }
        try promise.futureResult.wait()
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

    mutating func merge<S: Sequence>(_ others: S) -> ByteBuffer where S.Element == ByteBuffer {
        for var buffer in others {
            self.writeBuffer(&buffer)
        }
        return self
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

class HTTPResponseCompressorTest: XCTestCase {
    private enum WriteStrategy {
        case once
        case intermittentFlushes
    }

    private func sendRequest(acceptEncoding: String?, channel: EmbeddedChannel) throws {
        var requestHead = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "/")
        if let acceptEncoding = acceptEncoding {
            requestHead.headers.add(name: "Accept-Encoding", value: acceptEncoding)
        }
        try channel.writeInbound(HTTPServerRequestPart.head(requestHead))
        try channel.writeInbound(HTTPServerRequestPart.end(nil))
    }

    private func clientParsingChannel() -> EmbeddedChannel {
        let channel = EmbeddedChannel()
        XCTAssertNoThrow(try channel.pipeline.addHTTPClientHandlers().wait())
        return channel
    }

    private func writeOneChunk(head: HTTPResponseHead, body: [ByteBuffer], channel: EmbeddedChannel) throws {
        let promiseOrderer = PromiseOrderer(eventLoop: channel.eventLoop)
        channel.pipeline.write(NIOAny(HTTPServerResponsePart.head(head)), promise: promiseOrderer.makePromise())

        for bodyChunk in body {
            channel.pipeline.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(bodyChunk))),
                                   promise: promiseOrderer.makePromise())

        }
        channel.pipeline.write(NIOAny(HTTPServerResponsePart.end(nil)),
                               promise: promiseOrderer.makePromise())
        channel.pipeline.flush()

        // Get all the promises to fire.
        try promiseOrderer.waitUntilComplete()
    }

    private func writeIntermittentFlushes(head: HTTPResponseHead, body: [ByteBuffer], channel: EmbeddedChannel) throws {
        let promiseOrderer = PromiseOrderer(eventLoop: channel.eventLoop)
        var writeCount = 0
        channel.pipeline.write(NIOAny(HTTPServerResponsePart.head(head)), promise: promiseOrderer.makePromise())
        for bodyChunk in body {
            channel.pipeline.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(bodyChunk))),
                                   promise: promiseOrderer.makePromise())
            writeCount += 1
            if writeCount % 3 == 0 {
                channel.pipeline.flush()
            }
        }
        channel.pipeline.write(NIOAny(HTTPServerResponsePart.end(nil)),
                               promise: promiseOrderer.makePromise())
        channel.pipeline.flush()

        // Get all the promises to fire.
        try promiseOrderer.waitUntilComplete()
    }

    private func compressResponse(head: HTTPResponseHead,
                                  body: [ByteBuffer],
                                  channel: EmbeddedChannel,
                                  writeStrategy: WriteStrategy = .once) throws -> (HTTPResponseHead, [ByteBuffer]) {
        switch writeStrategy {
        case .once:
            try writeOneChunk(head: head, body: body, channel: channel)
        case .intermittentFlushes:
            try writeIntermittentFlushes(head: head, body: body, channel: channel)
        }

        // Feed the output from this channel into a client one. We need to have the client see a
        // HTTP request to avoid this exploding.
        let clientChannel = clientParsingChannel()
        defer {
            _ = try! clientChannel.finish()
        }
        var requestHead = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "/")
        requestHead.headers.add(name: "host", value: "apple.com")
        clientChannel.write(NIOAny(HTTPClientRequestPart.head(requestHead)), promise: nil)
        clientChannel.write(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)

        while let b = try channel.readOutbound(as: ByteBuffer.self) {
            try clientChannel.writeInbound(b)
        }

        // The first inbound datum will be the response head. The rest will be byte buffers, until
        // the last, which is the end.
        var head: HTTPResponseHead? = nil
        var dataChunks = [ByteBuffer]()
        loop: while let responsePart: HTTPClientResponsePart = try clientChannel.readInbound() {
            switch responsePart {
            case .head(let h):
                precondition(head == nil)
                head = h
            case .body(let data):
                dataChunks.append(data)
            case .end:
                break loop
            }
        }

        return (head!, dataChunks)
    }

    private func assertDecompressedResponseMatches(responseData: inout ByteBuffer,
                                                   expectedResponse: ByteBuffer,
                                                   allocator: ByteBufferAllocator,
                                                   decompressor: (inout ByteBuffer, inout ByteBuffer) -> Void) {
        var outputBuffer = allocator.buffer(capacity: expectedResponse.readableBytes)
        decompressor(&responseData, &outputBuffer)
        XCTAssertEqual(expectedResponse, outputBuffer)
    }

    private func assertDeflatedResponse(channel: EmbeddedChannel, writeStrategy: WriteStrategy = .once) throws {
        let bodySize = 2048
        let response = HTTPResponseHead(version: HTTPVersion(major: 1, minor: 1),
                                        status: .ok)
        let body = [UInt8](repeating: 60, count: bodySize)
        var bodyBuffer = channel.allocator.buffer(capacity: bodySize)
        bodyBuffer.writeBytes(body)

        var bodyChunks = [ByteBuffer]()
        for index in stride(from: 0, to: bodyBuffer.readableBytes, by: 2) {
            bodyChunks.append(bodyBuffer.getSlice(at: index, length: 2)!)
        }

        let data = try compressResponse(head: response,
                                        body: bodyChunks,
                                        channel: channel,
                                        writeStrategy: writeStrategy)
        let compressedResponse = data.0
        var compressedChunks = data.1
        var compressedBody = compressedChunks[0].merge(compressedChunks[1...])
        XCTAssertEqual(compressedResponse.headers[canonicalForm: "content-encoding"], ["deflate"])

        switch writeStrategy {
        case .once:
            XCTAssertEqual(compressedResponse.headers[canonicalForm: "content-length"], ["\(compressedBody.readableBytes)"])
            XCTAssertEqual(compressedResponse.headers[canonicalForm: "transfer-encoding"], [])
        case .intermittentFlushes:
            XCTAssertEqual(compressedResponse.headers[canonicalForm: "content-length"], [])
            XCTAssertEqual(compressedResponse.headers[canonicalForm: "transfer-encoding"], ["chunked"])
        }

        assertDecompressedResponseMatches(responseData: &compressedBody,
                                          expectedResponse: bodyBuffer,
                                          allocator: channel.allocator,
                                          decompressor: z_stream.decompressDeflate)
    }

    private func assertGzippedResponse(channel: EmbeddedChannel, writeStrategy: WriteStrategy = .once, additionalHeaders: HTTPHeaders = HTTPHeaders()) throws {
        let bodySize = 2048
        var response = HTTPResponseHead(version: HTTPVersion(major: 1, minor: 1),
                                        status: .ok)
        response.headers = additionalHeaders
        let body = [UInt8](repeating: 60, count: bodySize)
        var bodyBuffer = channel.allocator.buffer(capacity: bodySize)
        bodyBuffer.writeBytes(body)

        var bodyChunks = [ByteBuffer]()
        for index in stride(from: 0, to: bodyBuffer.readableBytes, by: 2) {
            bodyChunks.append(bodyBuffer.getSlice(at: index, length: 2)!)
        }

        let data = try compressResponse(head: response,
                                        body: bodyChunks,
                                        channel: channel,
                                        writeStrategy: writeStrategy)
        let compressedResponse = data.0
        var compressedChunks = data.1
        var compressedBody = compressedChunks[0].merge(compressedChunks[1...])
        XCTAssertEqual(compressedResponse.headers[canonicalForm: "content-encoding"], ["gzip"])

        switch writeStrategy {
        case .once:
            XCTAssertEqual(compressedResponse.headers[canonicalForm: "content-length"], ["\(compressedBody.readableBytes)"])
            XCTAssertEqual(compressedResponse.headers[canonicalForm: "transfer-encoding"], [])
        case .intermittentFlushes:
            XCTAssertEqual(compressedResponse.headers[canonicalForm: "content-length"], [])
            XCTAssertEqual(compressedResponse.headers[canonicalForm: "transfer-encoding"], ["chunked"])
        }

        assertDecompressedResponseMatches(responseData: &compressedBody,
                                          expectedResponse: bodyBuffer,
                                          allocator: channel.allocator,
                                          decompressor: z_stream.decompressGzip)
    }

    private func assertUncompressedResponse(channel: EmbeddedChannel, writeStrategy: WriteStrategy = .once) throws {
        let bodySize = 2048
        let response = HTTPResponseHead(version: HTTPVersion(major: 1, minor: 1),
                                        status: .ok)
        let body = [UInt8](repeating: 60, count: bodySize)
        var bodyBuffer = channel.allocator.buffer(capacity: bodySize)
        bodyBuffer.writeBytes(body)

        var bodyChunks = [ByteBuffer]()
        for index in stride(from: 0, to: bodyBuffer.readableBytes, by: 2) {
            bodyChunks.append(bodyBuffer.getSlice(at: index, length: 2)!)
        }

        let data = try compressResponse(head: response,
                                        body: bodyChunks,
                                        channel: channel,
                                        writeStrategy: writeStrategy)
        let compressedResponse = data.0
        var compressedChunks = data.1
        let uncompressedBody = compressedChunks[0].merge(compressedChunks[1...])
        XCTAssertEqual(compressedResponse.headers[canonicalForm: "content-encoding"], [])
        XCTAssertEqual(uncompressedBody.readableBytes, 2048)
        XCTAssertEqual(uncompressedBody, bodyBuffer)
    }

    private func compressionChannel() throws -> EmbeddedChannel {
        let channel = EmbeddedChannel()
        XCTAssertNoThrow(try channel.pipeline.addHandler(HTTPResponseEncoder(), name: "encoder").wait())
        XCTAssertNoThrow(try channel.pipeline.addHandler(HTTPResponseCompressor(), name: "compressor").wait())
        return channel
    }

    func testCanCompressSimpleBodies() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: "deflate", channel: channel)
        try assertDeflatedResponse(channel: channel)
    }

    func testCanCompressSimpleBodiesGzip() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: "gzip", channel: channel)
        try assertGzippedResponse(channel: channel)
    }

    func testCanCompressDeflateWithAwkwardFlushes() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: "deflate", channel: channel)
        try assertDeflatedResponse(channel: channel, writeStrategy: .intermittentFlushes)
    }

    func testCanCompressGzipWithAwkwardFlushes() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: "gzip", channel: channel)
        try assertGzippedResponse(channel: channel, writeStrategy: .intermittentFlushes)
    }

    func testDoesNotCompressWithoutAcceptEncodingHeader() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: nil, channel: channel)
        try assertUncompressedResponse(channel: channel)
    }

    func testHandlesPipelinedRequestsProperly() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        // Three requests: one for deflate, one for gzip, one for nothing.
        try sendRequest(acceptEncoding: "deflate", channel: channel)
        try sendRequest(acceptEncoding: "gzip", channel: channel)
        try sendRequest(acceptEncoding: "identity", channel: channel)

        try assertDeflatedResponse(channel: channel)
        try assertGzippedResponse(channel: channel)
        try assertUncompressedResponse(channel: channel)
    }

    func testHandlesBasicQValues() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: "gzip, deflate;q=0.5", channel: channel)
        try assertGzippedResponse(channel: channel)
    }

    func testAlwaysPrefersHighestQValue() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: "deflate;q=0.5, gzip;q=0.8, *;q=0.3", channel: channel)
        try assertGzippedResponse(channel: channel)
    }

    func testAsteriskMeansGzip() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: "*", channel: channel)
        try assertGzippedResponse(channel: channel)
    }

    func testIgnoresUnknownAlgorithms() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: "br", channel: channel)
        try assertUncompressedResponse(channel: channel)
    }

    func testNonNumericQValuePreventsChoice() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: "deflate;q=fish=fish, gzip;q=0.3", channel: channel)
        try assertGzippedResponse(channel: channel)
    }

    func testNaNQValuePreventsChoice() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: "deflate;q=NaN, gzip;q=0.3", channel: channel)
        try assertGzippedResponse(channel: channel)
    }

    func testInfinityQValuePreventsChoice() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: "deflate;q=Inf, gzip;q=0.3", channel: channel)
        try assertGzippedResponse(channel: channel)
    }

    func testNegativeInfinityQValuePreventsChoice() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: "deflate;q=-Inf, gzip;q=0.3", channel: channel)
        try assertGzippedResponse(channel: channel)
    }

    func testOutOfRangeQValuePreventsChoice() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: "deflate;q=2.2, gzip;q=0.3", channel: channel)
        try assertGzippedResponse(channel: channel)
    }

    func testOverridesContentEncodingHeader() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: "deflate;q=2.2, gzip;q=0.3", channel: channel)
        try assertGzippedResponse(channel: channel, additionalHeaders: HTTPHeaders([("Content-Encoding", "deflate")]))
    }

    func testRemovingHandlerFailsPendingWrites() throws {
        let channel = try compressionChannel()
        try sendRequest(acceptEncoding: "gzip", channel: channel)
        let head = HTTPResponseHead(version: HTTPVersion(major: 1, minor: 1), status: .ok)
        let writePromise = channel.eventLoop.makePromise(of: Void.self)
        channel.write(NIOAny(HTTPServerResponsePart.head(head)), promise: writePromise)
        writePromise.futureResult.map {
            XCTFail("Write succeeded")
        }.whenFailure { err in
            switch err {
            case HTTPResponseCompressor.CompressionError.uncompressedWritesPending:
                ()
                // ok
            default:
                XCTFail("\(err)")
            }
        }

        XCTAssertNoThrow(try channel.pipeline.removeHandler(name: "compressor").wait())

        do {
            try writePromise.futureResult.wait()
        } catch {
            // We don't care about errors here, we just need to block the
            // test until we're done.
        }
    }

    func testDoesNotBufferWritesNoAlgorithm() throws {
        let channel = try compressionChannel()
        try sendRequest(acceptEncoding: nil, channel: channel)
        let head = HTTPResponseHead(version: HTTPVersion(major: 1, minor: 1), status: .ok)
        let writePromise = channel.eventLoop.makePromise(of: Void.self)
        channel.writeAndFlush(NIOAny(HTTPServerResponsePart.head(head)), promise: writePromise)

        XCTAssertNoThrow(try channel.pipeline.removeHandler(name: "encoder").wait())
        XCTAssertNoThrow(try channel.pipeline.removeHandler(name: "compressor").wait())
        XCTAssertNoThrow(try writePromise.futureResult.wait())
    }
    
    func testChunkedGzipResponseProducesCorrectNumberOfWrites() throws {
        let channel = try compressionChannel()
        try sendRequest(acceptEncoding: "gzip", channel: channel)
        let finalPromise = channel.eventLoop.makePromise(of: Void.self)
        let head = HTTPResponseHead(version: HTTPVersion(major: 1, minor: 1), status: .ok)
        var bodyBuffer = channel.allocator.buffer(capacity: 20)
        bodyBuffer.writeBytes([UInt8](repeating: 60, count: 20))

        channel.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)
        channel.writeAndFlush(NIOAny(HTTPServerResponsePart.body(.byteBuffer(bodyBuffer))), promise: nil)
        channel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: finalPromise)
        
        try finalPromise.futureResult.wait()
        
        var writeCount = 0
        while try channel.readOutbound(as: ByteBuffer.self) != nil {
            writeCount += 1
        }
        
        // Expected number of emitted writes in the chunked response is 8:
        //   1. HTTP response header
        //   2. First chunk length
        //   3. First chunk body
        //   4. CRLF
        //   5. Second chunk length
        //   6. Second chunk body
        //   7. CRLF
        //   8. End of message chunk
        XCTAssertEqual(writeCount, 8)
    }

    func testStartsWithSameUnicodeScalarsWorksOnEmptyStrings() throws {
        XCTAssertTrue("".startsWithSameUnicodeScalars(string: ""))
    }

    func testStartsWithSameUnicodeScalarsWorksOnLongerNeedleFalse() throws {
        XCTAssertFalse("_".startsWithSameUnicodeScalars(string: "__"))
    }

    func testStartsWithSameUnicodeScalarsWorksOnSameStrings() throws {
        XCTAssertTrue("beer".startsWithSameUnicodeScalars(string: "beer"))
    }

    func testStartsWithSameUnicodeScalarsWorksOnPrefix() throws {
        XCTAssertTrue("beer is good".startsWithSameUnicodeScalars(string: "beer"))
    }

    func testStartsWithSameUnicodeScalarsSaysNoForTheSameStringInDifferentNormalisations() throws {
        let nfcEncodedEAigu = "\u{e9}"
        let nfdEncodedEAigu = "\u{65}\u{301}"

        XCTAssertEqual(nfcEncodedEAigu, nfdEncodedEAigu)
        XCTAssertTrue(nfcEncodedEAigu.startsWithSameUnicodeScalars(string: nfcEncodedEAigu))
        XCTAssertTrue(nfdEncodedEAigu.startsWithSameUnicodeScalars(string: nfdEncodedEAigu))
        // the both do _not_ start like the other
        XCTAssertFalse(nfcEncodedEAigu.startsWithSameUnicodeScalars(string: nfdEncodedEAigu))
        XCTAssertFalse(nfdEncodedEAigu.startsWithSameUnicodeScalars(string: nfcEncodedEAigu))
    }

    func testStartsWithSaysYesForTheSameStringInDifferentNormalisations() throws {
        let nfcEncodedEAigu = "\u{e9}"
        let nfdEncodedEAigu = "\u{65}\u{301}"

        XCTAssertEqual(nfcEncodedEAigu, nfdEncodedEAigu)
        XCTAssertTrue(nfcEncodedEAigu.starts(with: nfcEncodedEAigu))
        XCTAssertTrue(nfdEncodedEAigu.starts(with: nfdEncodedEAigu))
        // the both do start like the other as we do unicode normalisation
        XCTAssertTrue(nfcEncodedEAigu.starts(with: nfdEncodedEAigu))
        XCTAssertTrue(nfdEncodedEAigu.starts(with: nfcEncodedEAigu))
    }

    func testCanBeRemoved() throws {
        let channel = try compressionChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try sendRequest(acceptEncoding: "deflate", channel: channel)
        try assertDeflatedResponse(channel: channel)

        XCTAssertNoThrow(try channel.pipeline.context(handlerType: HTTPResponseCompressor.self).flatMap { context in
            channel.pipeline.removeHandler(context: context)
        }.wait())

        try sendRequest(acceptEncoding: "deflate", channel: channel)
        try assertUncompressedResponse(channel: channel)
    }
}

extension EventLoopFuture {
    var isFulfilled: Bool {
        if self.eventLoop.inEventLoop {
            // Easy, we're on the EventLoop. Let's just use our knowledge that we run completed future callbacks
            // immediately.
            var fulfilled = false
            self.whenComplete { _ in
                fulfilled = true
            }
            return fulfilled
        } else {
            let lock = Lock()
            let group = DispatchGroup()
            var fulfilled = false // protected by lock

            group.enter()
            self.eventLoop.execute {
                let isFulfilled = self.isFulfilled // This will now enter the above branch.
                lock.withLock {
                    fulfilled = isFulfilled
                }
                group.leave()
            }
            group.wait() // this is very nasty but this is for tests only, so...
            return lock.withLock { fulfilled }
        }
    }
}
