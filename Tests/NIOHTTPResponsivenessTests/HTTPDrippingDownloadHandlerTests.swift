//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2024 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import HTTPTypes
import NIOCore
import NIOEmbedded
import NIOHTTPTypes
import XCTest

@testable import NIOHTTPResponsiveness

final class HTTPDrippingDownloadHandlerTests: XCTestCase {

    func testDefault() throws {
        let eventLoop = EmbeddedEventLoop()
        let channel = EmbeddedChannel(handler: HTTPDrippingDownloadHandler(), loop: eventLoop)

        try channel.writeInbound(
            HTTPRequestPart.head(HTTPRequest(method: .get, scheme: "http", authority: "whatever", path: "/drip"))
        )

        eventLoop.run()

        guard case let HTTPResponsePart.head(head) = (try channel.readOutbound())! else {
            XCTFail("expected response head")
            return
        }
        XCTAssertEqual(head.status, .ok)

        guard case HTTPResponsePart.end(nil) = (try channel.readOutbound())! else {
            XCTFail("expected response end")
            return
        }

        let _ = try channel.finish()
    }

    func testBasic() throws {
        try dripTest(count: 2, size: 1024)
    }

    func testZeroChunks() throws {
        try dripTest(count: 0)
    }

    func testNonZeroStatusCode() throws {
        try dripTest(count: 1, code: .notAcceptable)
    }

    func testZeroChunkSize() throws {
        try dripTest(count: 1, size: 0)
    }

    func dripTest(
        count: Int,
        size: Int = 1024,
        frequency: TimeAmount = .seconds(1),
        delay: TimeAmount = .seconds(5),
        code: HTTPResponse.Status = .ok
    ) throws {
        #if compiler(>=6.2) && compiler(<6.3) && !canImport(Darwin)
        throw XCTSkip("Runtime has runtime crashes that make this test useless on non-Apple platforms")
        #else
        let eventLoop = EmbeddedEventLoop()
        let channel = EmbeddedChannel(
            handler: HTTPDrippingDownloadHandler(
                count: count,
                size: size,
                frequency: frequency,
                delay: delay,
                code: code
            ),
            loop: eventLoop
        )

        try channel.writeInbound(
            HTTPRequestPart.head(HTTPRequest(method: .get, scheme: "http", authority: "whatever", path: nil))
        )

        // Make sure delay is honored
        eventLoop.run()
        XCTAssert(try channel.readOutbound() == nil)

        eventLoop.advanceTime(by: delay + .milliseconds(100))

        guard case let HTTPResponsePart.head(head) = (try channel.readOutbound())! else {
            XCTFail("expected response head")
            return
        }
        XCTAssertEqual(head.status, code)

        var chunksReceived = 0
        while chunksReceived < count {

            // Shouldn't need to wait for the first chunk
            if chunksReceived > 0 {
                eventLoop.advanceTime(by: frequency + .milliseconds(100))
            }

            var chunkBytesReceived = 0
            while chunkBytesReceived < size {
                let next: HTTPResponsePart? = try channel.readOutbound()
                guard case let .body(dataChunk) = next! else {
                    XCTFail("expected response data")
                    return
                }
                chunkBytesReceived += dataChunk.readableBytes
            }
            chunksReceived += 1

            if chunksReceived < count {
                let part: HTTPResponsePart? = try channel.readOutbound()
                XCTAssert(part == nil)
            }
        }

        guard case HTTPResponsePart.end(nil) = (try channel.readOutbound())! else {
            XCTFail("expected response end")
            return
        }

        let _ = try channel.finish()
        #endif
    }

}
