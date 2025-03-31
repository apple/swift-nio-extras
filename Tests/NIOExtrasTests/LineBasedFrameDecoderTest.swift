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

import NIOEmbedded
import NIOExtras
import NIOTestUtils
import XCTest

@testable import NIOCore  // to inspect the cumulationBuffer

class LineBasedFrameDecoderTest: XCTestCase {
    private var channel: EmbeddedChannel!
    private var decoder: LineBasedFrameDecoder!
    private var handler: ByteToMessageHandler<LineBasedFrameDecoder>!

    override func setUp() {
        self.channel = EmbeddedChannel()
        self.decoder = LineBasedFrameDecoder()
        self.handler = ByteToMessageHandler(self.decoder)
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.handler))
    }

    override func tearDown() {
        self.decoder = nil
        self.handler = nil
        _ = try? self.channel.finish()
    }

    func testDecodeOneCharacterAtATime() throws {
        let message = "abcdefghij\r"
        // we write one character at a time
        for character in message {
            var buffer = self.channel.allocator.buffer(capacity: 1)
            buffer.writeString("\(character)")
            XCTAssertTrue(try self.channel.writeInbound(buffer).isEmpty)
        }
        // let's add `\n`
        var buffer = self.channel.allocator.buffer(capacity: 1)
        buffer.writeString("\n")
        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)

        XCTAssertNoThrow(
            XCTAssertEqual(
                "abcdefghij",
                (try self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                    String(decoding: $0[0..<10], as: Unicode.UTF8.self)
                }
            )
        )
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testRemoveHandlerWhenBufferIsNotEmpty() throws {
        var buffer = self.channel.allocator.buffer(capacity: 8)
        buffer.writeString("foo\r\nbar")
        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)
        var outputBuffer: ByteBuffer? = try self.channel.readInbound()
        XCTAssertEqual(3, outputBuffer?.readableBytes)
        XCTAssertEqual("foo", outputBuffer?.readString(length: 3))

        let removeFuture = self.channel.pipeline.syncOperations.removeHandler(self.handler)
        (self.channel.eventLoop as! EmbeddedEventLoop).run()
        XCTAssertNoThrow(try removeFuture.wait())
        XCTAssertThrowsError(try self.channel.throwIfErrorCaught()) { error in
            guard let error = error as? NIOExtrasErrors.LeftOverBytesError else {
                XCTFail()
                return
            }

            var expectedBuffer = self.channel.allocator.buffer(capacity: 7)
            expectedBuffer.writeString("bar")
            XCTAssertEqual(error.leftOverBytes, expectedBuffer)
        }
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testRemoveHandlerWhenBufferIsEmpty() throws {
        var buffer = self.channel.allocator.buffer(capacity: 4)
        buffer.writeString("foo\n")
        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)

        var outputBuffer: ByteBuffer? = try self.channel.readInbound()
        XCTAssertEqual("foo", outputBuffer?.readString(length: 3))

        let removeFuture = self.channel.pipeline.syncOperations.removeHandler(self.handler)
        (self.channel.eventLoop as! EmbeddedEventLoop).run()
        XCTAssertNoThrow(try removeFuture.wait())
        XCTAssertNoThrow(try self.channel.throwIfErrorCaught())
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testEmptyLine() throws {
        var buffer = self.channel.allocator.buffer(capacity: 1)
        buffer.writeString("\n")
        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)

        var outputBuffer: ByteBuffer? = try self.channel.readInbound()
        XCTAssertEqual("", outputBuffer?.readString(length: 0))
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testEmptyBuffer() throws {
        var buffer = self.channel.allocator.buffer(capacity: 1)
        buffer.writeString("")
        XCTAssertTrue(try self.channel.writeInbound(buffer).isEmpty)
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testChannelInactiveWithLeftOverBytes() throws {
        // add some data to the buffer
        var buffer = self.channel.allocator.buffer(capacity: 2)
        // read "abc" so the reader index is not 0
        buffer.writeString("hi")
        XCTAssertTrue(try self.channel.writeInbound(buffer).isEmpty)

        try self.channel.close().wait()
        XCTAssertThrowsError(try self.channel.throwIfErrorCaught()) { error in
            guard let error = error as? NIOExtrasErrors.LeftOverBytesError else {
                XCTFail()
                return
            }
            var expectedBuffer = self.channel.allocator.buffer(capacity: 7)
            expectedBuffer.writeString("hi")
            XCTAssertEqual(error.leftOverBytes, expectedBuffer)
        }
    }

    func testMoreDataAvailableWhenChannelBecomesInactive() throws {
        class CloseWhenMyFavouriteMessageArrives: ChannelInboundHandler {
            typealias InboundIn = ByteBuffer

            private let receivedLeftOversPromise: EventLoopPromise<ByteBuffer>

            init(receivedLeftOversPromise: EventLoopPromise<ByteBuffer>) {
                self.receivedLeftOversPromise = receivedLeftOversPromise
            }

            func channelRead(context: ChannelHandlerContext, data: NIOAny) {
                let buffer = self.unwrapInboundIn(data)
                context.fireChannelRead(data)

                if buffer.readableBytes == 3 {
                    context.close(promise: nil)
                }
            }

            func errorCaught(context: ChannelHandlerContext, error: Error) {
                if let leftOvers = error as? NIOExtrasErrors.LeftOverBytesError {
                    self.receivedLeftOversPromise.succeed(leftOvers.leftOverBytes)
                } else {
                    context.fireErrorCaught(error)
                }
            }
        }
        let receivedLeftOversPromise: EventLoopPromise<ByteBuffer> = self.channel.eventLoop.makePromise()
        let handler = CloseWhenMyFavouriteMessageArrives(receivedLeftOversPromise: receivedLeftOversPromise)
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(handler))
        var buffer = self.channel.allocator.buffer(capacity: 16)
        buffer.writeString("a\nbb\nccc\ndddd\neeeee\nffffff\nXXX")
        XCTAssertNoThrow(try self.channel.writeInbound(buffer))
        for s in ["a", "bb", "ccc", "dddd", "eeeee", "ffffff"] {
            XCTAssertNoThrow(
                XCTAssertEqual(
                    s,
                    (try self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                        String(decoding: $0, as: Unicode.UTF8.self)
                    }
                )
            )
        }
        XCTAssertNoThrow(XCTAssertNil(try self.channel.readInbound(as: ByteBuffer.self)))
        XCTAssertNoThrow(
            try XCTAssertEqual(
                "XXX",
                String(
                    decoding: receivedLeftOversPromise.futureResult.wait().readableBytesView,
                    as: UTF8.self
                )
            )
        )
    }

    func testDripFedCRLN() {
        var buffer = self.channel.allocator.buffer(capacity: 1)

        for byte in ["a", "\r", "\n"].flatMap({ $0.utf8 }) {
            buffer.clear()
            buffer.writeInteger(byte)
            XCTAssertNoThrow(try self.channel.writeInbound(buffer))
        }
        buffer.clear()
        buffer.writeString("a")
        XCTAssertNoThrow(XCTAssertEqual(buffer, try self.channel.readInbound()))
    }

    func testBasicValidation() {
        func byteBuffer(_ string: String) -> ByteBuffer {
            var buffer = self.channel.allocator.buffer(capacity: string.utf8.count)
            buffer.writeString(string)
            return buffer
        }

        do {
            try ByteToMessageDecoderVerifier.verifyDecoder(stringInputOutputPairs: [
                ("\n", [byteBuffer("")]),
                ("\r\n", [byteBuffer("")]),
                ("a\r\n", [byteBuffer("a")]),
                ("a\n", [byteBuffer("a")]),
                ("a\rb\n", [byteBuffer("a\rb")]),
                (
                    "Content-Length: 17\r\nConnection: close\r\n\r\n",
                    [
                        byteBuffer("Content-Length: 17"),
                        byteBuffer("Connection: close"),
                        byteBuffer(""),
                    ]
                ),
            ]) {
                LineBasedFrameDecoder()
            }
        } catch {
            print(error)
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBasicSingleStep() {
        let decoder = LineBasedFrameDecoder()
        let b2mp = NIOSingleStepByteToMessageProcessor(decoder)
        var callCount = 0
        XCTAssertNoThrow(
            try b2mp.process(buffer: ByteBuffer(string: "1\n\n2\n3\n")) { line in
                callCount += 1
                switch callCount {
                case 1:
                    XCTAssertEqual(ByteBuffer(string: "1"), line)
                case 2:
                    XCTAssertEqual(ByteBuffer(string: ""), line)
                case 3:
                    XCTAssertEqual(ByteBuffer(string: "2"), line)
                case 4:
                    XCTAssertEqual(ByteBuffer(string: "3"), line)
                default:
                    XCTFail("not expecting call no \(callCount)")
                }
            }
        )
    }

    func testBasicSingleStepNoNewlineComingButEOF() {
        let decoder = LineBasedFrameDecoder()
        let b2mp = NIOSingleStepByteToMessageProcessor(decoder)
        XCTAssertNoThrow(
            try b2mp.process(buffer: ByteBuffer(string: "new newline eva\r")) { line in
                XCTFail("not taking calls")
            }
        )
        XCTAssertThrowsError(
            try b2mp.finishProcessing(
                seenEOF: true,
                { line in
                    XCTFail("not taking calls")
                }
            )
        ) { error in
            if let error = error as? NIOExtrasErrors.LeftOverBytesError {
                XCTAssertEqual(ByteBuffer(string: "new newline eva\r"), error.leftOverBytes)
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testBasicSingleStepNoNewlineOrEOFComing() {
        let decoder = LineBasedFrameDecoder()
        let b2mp = NIOSingleStepByteToMessageProcessor(decoder)
        XCTAssertNoThrow(
            try b2mp.process(buffer: ByteBuffer(string: "new newline eva\r")) { line in
                XCTFail("not taking calls")
            }
        )
        XCTAssertThrowsError(
            try b2mp.finishProcessing(
                seenEOF: false,
                { line in
                    XCTFail("not taking calls")
                }
            )
        ) { error in
            if let error = error as? NIOExtrasErrors.LeftOverBytesError {
                XCTAssertEqual(ByteBuffer(string: "new newline eva\r"), error.leftOverBytes)
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testBasicSingleStepEOFDuringDecoding() {
        let decoder = LineBasedFrameDecoder()
        let b2mp = NIOSingleStepByteToMessageProcessor(decoder)
        var callCount = 0
        XCTAssertNoThrow(
            try b2mp.process(buffer: ByteBuffer(string: "1\n\n2\n3\n")) { line in
                callCount += 1
                switch callCount {
                case 1:
                    XCTAssertEqual(ByteBuffer(string: "1"), line)
                    XCTAssertNoThrow(try b2mp.finishProcessing(seenEOF: true) { _ in })
                case 2:
                    XCTAssertEqual(ByteBuffer(string: ""), line)
                case 3:
                    XCTAssertEqual(ByteBuffer(string: "2"), line)
                case 4:
                    XCTAssertEqual(ByteBuffer(string: "3"), line)
                default:
                    XCTFail("not expecting call no \(callCount)")
                }
            }
        )
    }
}
