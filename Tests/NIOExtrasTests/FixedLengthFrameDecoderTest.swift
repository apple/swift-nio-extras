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

import NIOCore
import NIOEmbedded
import NIOExtras
import NIOTestUtils
import XCTest

class FixedLengthFrameDecoderTest: XCTestCase {
    public func testDecodeIfFewerBytesAreSent() throws {
        let channel = EmbeddedChannel()

        let frameLength = 8
        try channel.pipeline.syncOperations.addHandler(
            ByteToMessageHandler(FixedLengthFrameDecoder(frameLength: frameLength))
        )

        var buffer = channel.allocator.buffer(capacity: frameLength)
        buffer.writeString("xxxx")
        XCTAssertTrue(try channel.writeInbound(buffer).isEmpty)
        XCTAssertTrue(try channel.writeInbound(buffer).isFull)

        XCTAssertEqual(
            "xxxxxxxx",
            try (channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                String(decoding: $0, as: Unicode.UTF8.self)
            }
        )
        XCTAssertTrue(try channel.finish().isClean)
    }

    public func testDecodeIfMoreBytesAreSent() throws {
        let channel = EmbeddedChannel()

        let frameLength = 8
        try channel.pipeline.syncOperations.addHandler(
            ByteToMessageHandler(FixedLengthFrameDecoder(frameLength: frameLength))
        )

        var buffer = channel.allocator.buffer(capacity: 19)
        buffer.writeString("xxxxxxxxaaaaaaaabbb")
        XCTAssertTrue(try channel.writeInbound(buffer).isFull)

        XCTAssertEqual(
            "xxxxxxxx",
            try (channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                String(decoding: $0, as: Unicode.UTF8.self)
            }
        )

        XCTAssertEqual(
            "aaaaaaaa",
            try (channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                String(decoding: $0, as: Unicode.UTF8.self)
            }
        )

        XCTAssertNoThrow(XCTAssertNil(try channel.readInbound(as: ByteBuffer.self)))
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
        try channel.pipeline.syncOperations.addHandler(handler)

        var buffer = channel.allocator.buffer(capacity: 15)
        buffer.writeString("xxxxxxxxxxxxxxx")
        XCTAssertTrue(try channel.writeInbound(buffer).isFull)

        XCTAssertEqual(
            "xxxxxxxx",
            try (channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                String(decoding: $0, as: Unicode.UTF8.self)
            }
        )

        let removeFuture = channel.pipeline.syncOperations.removeHandler(handler)
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
        XCTAssertTrue(try channel.finish().isClean)
    }

    public func testRemoveHandlerWhenBufferIsEmpty() throws {
        let channel = EmbeddedChannel()

        let frameLength = 8
        let handler = ByteToMessageHandler(FixedLengthFrameDecoder(frameLength: frameLength))
        try channel.pipeline.syncOperations.addHandler(handler)

        var buffer = channel.allocator.buffer(capacity: 6)
        buffer.writeString("xxxxxxxx")
        XCTAssertTrue(try channel.writeInbound(buffer).isFull)

        XCTAssertEqual(
            "xxxxxxxx",
            try (channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                String(decoding: $0, as: Unicode.UTF8.self)
            }
        )

        let removeFuture = channel.pipeline.syncOperations.removeHandler(handler)
        (channel.eventLoop as! EmbeddedEventLoop).run()
        XCTAssertNoThrow(try removeFuture.wait())
        XCTAssertNoThrow(try channel.throwIfErrorCaught())
        XCTAssertTrue(try channel.finish().isClean)
    }

    func testBasicValidation() {
        for length in 1...20 {
            let inputs = [
                String(decoding: Array(repeating: UInt8(ascii: "a"), count: length), as: Unicode.UTF8.self),
                String(decoding: Array(repeating: UInt8(ascii: "b"), count: length), as: Unicode.UTF8.self),
                String(decoding: Array(repeating: UInt8(ascii: "c"), count: length), as: Unicode.UTF8.self),
            ]
            func byteBuffer(_ string: String) -> ByteBuffer {
                var buffer = ByteBufferAllocator().buffer(capacity: string.utf8.count)
                buffer.writeString(string)
                return buffer
            }
            let inputOutputPairs: [(String, [ByteBuffer])] = inputs.map { ($0, [byteBuffer($0)]) }
            XCTAssertNoThrow(
                try ByteToMessageDecoderVerifier.verifyDecoder(stringInputOutputPairs: inputOutputPairs) {
                    FixedLengthFrameDecoder(frameLength: length)
                }
            )
        }
    }
}
