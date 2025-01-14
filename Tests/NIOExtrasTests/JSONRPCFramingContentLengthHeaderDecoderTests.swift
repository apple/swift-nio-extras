//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019-2021 Apple Inc. and the SwiftNIO project authors
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
import XCTest

final class JSONRPCFramingContentLengthHeaderDecoderTests: XCTestCase {
    private var channel: EmbeddedChannel!  // not a real network connection

    override func setUp() {
        self.channel = EmbeddedChannel()

        // let's add the framing handler to the pipeline as that's what we're testing here.
        XCTAssertNoThrow(
            try self.channel.pipeline.syncOperations.addHandler(
                ByteToMessageHandler(NIOJSONRPCFraming.ContentLengthHeaderFrameDecoder())
            )
        )
        // this pretends to connect the channel to this IP address.
        XCTAssertNoThrow(self.channel.connect(to: try .init(ipAddress: "1.2.3.4", port: 5678)))
    }

    override func tearDown() {
        if self.channel.isActive {
            // this makes sure that the channel is clean (no errors, no left-overs in the channel, etc)
            XCTAssertNoThrow(XCTAssertTrue(try self.channel.finish().isClean))
        }
        self.channel = nil
    }

    private func buffer(string: String) -> ByteBuffer {
        var buffer = self.channel.allocator.buffer(capacity: string.utf8.count)
        buffer.writeString(string)
        return buffer
    }

    private func buffer(byte: UInt8) -> ByteBuffer {
        var buffer = self.channel.allocator.buffer(capacity: 1)
        buffer.writeInteger(byte)
        return buffer
    }

    private func readInboundString() throws -> String? {
        try self.channel.readInbound(as: ByteBuffer.self).map {
            String(decoding: $0.readableBytesView, as: Unicode.UTF8.self)
        }
    }

    func testBasicMessage() {
        XCTAssertNoThrow(try self.channel.writeInbound(self.buffer(string: "Content-Length: 1\r\n\r\nX")))
        // we expect exactly one "X" to come out at the other end.
        XCTAssertNoThrow(try XCTAssertEqual("X", self.readInboundString()))
    }

    func testEmptyMessage() {
        XCTAssertNoThrow(try self.channel.writeInbound(self.buffer(string: "Content-Length: 0\r\n\r\n")))
        // we expect exactly one empty String to come out at the other end.
        XCTAssertNoThrow(try XCTAssertEqual("", self.readInboundString()))
    }

    func testWrongCasing() {
        XCTAssertNoThrow(try self.channel.writeInbound(self.buffer(string: "CoNtEnT-LeNgTh: 1\r\n\r\nX")))
        // we expect exactly one "X" to come out at the other end.
        XCTAssertNoThrow(try XCTAssertEqual("X", self.readInboundString()))
    }

    func testTechnicallyInvalidButWeAreNicePeople() {
        // this writes a bunch of messages that are technically not okay, but we're fine with them
        let coupleOfMessages =
            "Content-Length:1\r\n\r\nX"  // space after colon missing
            + "Content-Length : 1\r\n\r\nX"  // extra space before colon
            + " Content-Length: 1\r\n\r\nX"  // extra space at the beginning of the header
            + "Content-Length: 1\n\r\nX"  // \r missing

        XCTAssertNoThrow(try self.channel.writeInbound(self.buffer(string: coupleOfMessages)))

        for _ in 0..<4 {
            XCTAssertNoThrow(try XCTAssertEqual("X", self.readInboundString()))
        }
    }

    func testLongerMessage() {
        XCTAssertNoThrow(try self.channel.writeInbound(self.buffer(string: "Content-Length: 5\r\n\r\n12345")))
        XCTAssertNoThrow(try XCTAssertEqual("12345", self.readInboundString()))
    }

    func testSomePointlessExtraHeaders() {
        let s = "foo: bar\r\nContent-Length: 4\r\nbuz: qux\r\n\r\n1234"
        XCTAssertNoThrow(try self.channel.writeInbound(self.buffer(string: s)))
        XCTAssertNoThrow(try XCTAssertEqual("1234", self.readInboundString()))
    }

    func testDripAndMassFeedMessages() {
        let messagesAndExpectedOutput: [(String, String)] =
            [
                ("Content-Length: 1\r\n\r\n1", "1"),
                ("Content-Length: 0\r\n\r\n", ""),
                ("foo: bar\r\nContent-Length: 7\r\nbuz: qux\r\n\r\nqwerasd", "qwerasd"),
                ("content-lengTH:                1             \r\n\r\nX", "X"),
            ]

        // drip feed (byte by byte)
        for (message, expected) in messagesAndExpectedOutput {
            for byte in message.utf8 {
                // before the last byte, no output should happen
                XCTAssertNoThrow(XCTAssertNil(try channel.readInbound(), "premature output for '\(message)'"))

                XCTAssertNoThrow(try self.channel.writeInbound(self.buffer(byte: byte)))
            }
            XCTAssertNoThrow(try XCTAssertEqual(expected, self.readInboundString()))
        }

        // mass feed (many messages in one go)
        let everything = messagesAndExpectedOutput.map { $0.0 }.reduce("", +)
        // 3 times every message
        XCTAssertNoThrow(try self.channel.writeInbound(self.buffer(string: everything + everything + everything)))

        for _ in 0..<3 {
            for expected in messagesAndExpectedOutput.map({ $0.1 }) {
                XCTAssertNoThrow(try XCTAssertEqual(expected, self.readInboundString()))
            }
        }
    }

    func testErrorNoContentLengthHeader() {
        let s = "Content-Type: text/plain\r\n\r\n12345"
        XCTAssertThrowsError(try self.channel.writeInbound(self.buffer(string: s))) { error in
            if let error = error as? NIOJSONRPCFraming.ContentLengthHeaderFrameDecoder.DecodingError {
                XCTAssertEqual(.missingContentLengthHeader, error)
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
        // this shouldn't produce output
        XCTAssertNoThrow(try XCTAssertNil(self.channel.readInbound(as: ByteBuffer.self)))
    }

    func testErrorNotEnoughDataAtEOF() {
        let s = "Content-Length: 4\r\n\r\n123"  // only three bytes payload, not 4
        XCTAssertNoThrow(try self.channel.writeInbound(self.buffer(string: s)))
        XCTAssertNoThrow(try XCTAssertNil(self.channel.readInbound()))

        XCTAssertThrowsError(try self.channel.finish()) { error in
            if case .some(.leftoverDataWhenDone(let leftOvers)) = error as? ByteToMessageDecoderError {
                XCTAssertEqual("123", String(decoding: leftOvers.readableBytesView, as: Unicode.UTF8.self))
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testErrorNegativeContentLength() {
        let s = "Content-Length: -1\r\n\r\n"
        XCTAssertThrowsError(try self.channel.writeInbound(self.buffer(string: s))) { error in
            if let error = error as? NIOJSONRPCFraming.ContentLengthHeaderFrameDecoder.DecodingError {
                XCTAssertEqual(.illegalContentLengthHeaderValue(" -1\r\n"), error)
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
        // this shouldn't produce output
        XCTAssertNoThrow(try XCTAssertNil(self.channel.readInbound(as: ByteBuffer.self)))
    }

    func testErrorNotANumberContentLength() {
        let s = "Content-Length: a\r\n\r\n"
        XCTAssertThrowsError(try self.channel.writeInbound(self.buffer(string: s))) { error in
            if let error = error as? NIOJSONRPCFraming.ContentLengthHeaderFrameDecoder.DecodingError {
                XCTAssertEqual(.illegalContentLengthHeaderValue(" a\r\n"), error)
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
        // this shouldn't produce output
        XCTAssertNoThrow(try XCTAssertNil(self.channel.readInbound(as: ByteBuffer.self)))
    }
}
