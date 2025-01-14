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

final class JSONRPCFramingContentLengthHeaderEncoderTests: XCTestCase {
    private var channel: EmbeddedChannel!  // not a real network connection

    override func setUp() {
        self.channel = EmbeddedChannel()

        // let's add the framing handler to the pipeline as that's what we're testing here.
        XCTAssertNoThrow(
            try self.channel.pipeline.syncOperations.addHandler(NIOJSONRPCFraming.ContentLengthHeaderFrameEncoder())
        )
        // let's also add the decoder so we can round-trip
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

    private func readOutboundString() throws -> String? {
        try self.channel.readOutbound(as: ByteBuffer.self).map {
            String(decoding: $0.readableBytesView, as: Unicode.UTF8.self)
        }
    }

    func testEmptyMessage() {
        XCTAssertNoThrow(try self.channel.writeOutbound(self.channel.allocator.buffer(capacity: 0)))
        XCTAssertNoThrow(
            XCTAssertEqual(
                "Content-Length: 0\r\n\r\n",
                try self.readOutboundString()
            )
        )
        XCTAssertNoThrow(XCTAssertNil(try self.readOutboundString()))
    }

    func testRoundtrip() {
        var buffer = self.channel.allocator.buffer(capacity: 8)
        buffer.writeString("01234567")
        XCTAssertNoThrow(try self.channel.writeOutbound(buffer))
        XCTAssertNoThrow(
            try {
                while let encoded = try self.channel.readOutbound(as: ByteBuffer.self) {
                    // round trip it back
                    try self.channel.writeInbound(encoded)
                }
            }()
        )
        XCTAssertNoThrow(
            XCTAssertEqual(
                "01234567",
                try self.channel.readInbound(as: ByteBuffer.self).map {
                    String(decoding: $0.readableBytesView, as: Unicode.UTF8.self)
                }
            )
        )
    }
}
