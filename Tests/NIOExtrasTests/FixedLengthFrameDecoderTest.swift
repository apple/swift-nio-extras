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
import NIO
import NIOExtras

class FixedLengthFrameDecoderTest: XCTestCase {

    public func testDecodeIfFewerBytesAreSent() throws {
        let channel = EmbeddedChannel()

        let frameLength = 8
        try channel.pipeline.addHandler(ByteToMessageHandler(FixedLengthFrameDecoder(frameLength: frameLength))).wait()

        var buffer = channel.allocator.buffer(capacity: frameLength)
        buffer.writeString("xxxx")
        XCTAssertFalse(try channel.writeInbound(buffer))
        XCTAssertTrue(try channel.writeInbound(buffer))

        var outputBuffer: ByteBuffer? = channel.readInbound()
        XCTAssertEqual("xxxxxxxx", outputBuffer?.readString(length: frameLength))
        XCTAssertFalse(try channel.finish())
    }

    public func testDecodeIfMoreBytesAreSent() throws {
        let channel = EmbeddedChannel()

        let frameLength = 8
        try channel.pipeline.addHandler(ByteToMessageHandler(FixedLengthFrameDecoder(frameLength: frameLength))).wait()

        var buffer = channel.allocator.buffer(capacity: 19)
        buffer.writeString("xxxxxxxxaaaaaaaabbb")
        XCTAssertTrue(try channel.writeInbound(buffer))

        var outputBuffer: ByteBuffer? = channel.readInbound()
        XCTAssertEqual("xxxxxxxx", outputBuffer?.readString(length: frameLength))

        outputBuffer = channel.readInbound()
        XCTAssertEqual("aaaaaaaa", outputBuffer?.readString(length: frameLength))

        outputBuffer = channel.readInbound()
        XCTAssertNil(outputBuffer?.readString(length: frameLength))
        XCTAssertThrowsError(try channel.finish()) { error in
            if let error = error as? NIOExtrasErrors.LeftOverBytesError {
                XCTAssertEqual(3, error.leftOverBytes.readableBytes)
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    public func testRemoveHandlerWhenBufferIsNotEmpty() throws {
        let channel = EmbeddedChannel()

        let frameLength = 8
        let handler = ByteToMessageHandler(FixedLengthFrameDecoder(frameLength: frameLength))
        try channel.pipeline.addHandler(handler).wait()

        var buffer = channel.allocator.buffer(capacity: 15)
        buffer.writeString("xxxxxxxxxxxxxxx")
        XCTAssertTrue(try channel.writeInbound(buffer))

        var outputBuffer: ByteBuffer? = channel.readInbound()
        XCTAssertEqual("xxxxxxxx", outputBuffer?.readString(length: frameLength))

        let removeFuture = channel.pipeline.removeHandler(handler)
        (channel.eventLoop as! EmbeddedEventLoop).run()
        XCTAssertNoThrow(try removeFuture.wait())
        XCTAssertThrowsError(try channel.throwIfErrorCaught()) { error in
            guard let error = error as? NIOExtrasErrors.LeftOverBytesError else {
                XCTFail()
                return
            }

            var expectedBuffer = channel.allocator.buffer(capacity: 7)
            expectedBuffer.writeString("xxxxxxx")
            XCTAssertEqual(error.leftOverBytes, expectedBuffer)
        }
        XCTAssertFalse(try channel.finish())
    }

    public func testRemoveHandlerWhenBufferIsEmpty() throws {
        let channel = EmbeddedChannel()

        let frameLength = 8
        let handler = ByteToMessageHandler(FixedLengthFrameDecoder(frameLength: frameLength))
        try channel.pipeline.addHandler(handler).wait()

        var buffer = channel.allocator.buffer(capacity: 6)
        buffer.writeString("xxxxxxxx")
        XCTAssertTrue(try channel.writeInbound(buffer))

        var outputBuffer: ByteBuffer? = channel.readInbound()
        XCTAssertEqual("xxxxxxxx", outputBuffer?.readString(length: frameLength))

        let removeFuture = channel.pipeline.removeHandler(handler)
        (channel.eventLoop as! EmbeddedEventLoop).run()
        XCTAssertNoThrow(try removeFuture.wait())
        XCTAssertNoThrow(try channel.throwIfErrorCaught())
        XCTAssertFalse(try channel.finish())
    }

    func testCloseInChannelRead() {
        let channel = EmbeddedChannel(handler: ByteToMessageHandler(LengthFieldBasedFrameDecoder(lengthFieldLength: .four)))
        class CloseInReadHandler: ChannelInboundHandler {
            typealias InboundIn = ByteBuffer

            private var numberOfReads = 0

            func channelRead(context: ChannelHandlerContext, data: NIOAny) {
                self.numberOfReads += 1
                XCTAssertEqual(1, self.numberOfReads)
                XCTAssertEqual([UInt8(100)], Array(self.unwrapInboundIn(data).readableBytesView))
                context.close().whenFailure { error in
                    XCTFail("unexpected error: \(error)")
                }
                context.fireChannelRead(data)
            }
        }
        XCTAssertNoThrow(try channel.pipeline.addHandler(CloseInReadHandler()).wait())

        var buf = channel.allocator.buffer(capacity: 1024)
        buf.writeBytes([UInt8(0), 0, 0, 1, 100])
        XCTAssertNoThrow(try channel.writeInbound(buf))
        XCTAssertEqual([100], Array((channel.readInbound() as ByteBuffer?)!.readableBytesView))
        XCTAssertNil(channel.readInbound())

    }
}
