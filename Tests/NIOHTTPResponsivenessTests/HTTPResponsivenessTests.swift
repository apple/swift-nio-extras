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

final class NIOHTTPResponsivenessTests: XCTestCase {
    func download(channel: EmbeddedChannel, n: Int) throws {
        // Recv head
        try channel.writeInbound(
            HTTPRequestPart.head(
                HTTPRequest(
                    method: .get,
                    scheme: "http",
                    authority: "localhost:8888",
                    path: "/responsiveness/download/\(n)"
                )
            )
        )

        // Should get response head with content length
        let out: HTTPResponsePart = (try channel.readOutbound())!
        guard case let HTTPResponsePart.head(head) = out else {
            XCTFail()
            return
        }
        XCTAssertEqual(Int(head.headerFields[.contentLength]!)!, n)

        // Drain response body until completed
        var received = 0
        loop: while true {
            let out: HTTPResponsePart = (try channel.readOutbound())!
            switch out {
            case .head:
                XCTFail("cannot get head twice")
            case .body(let body):
                received += body.readableBytes
            case .end:
                break loop
            }
        }
        XCTAssertEqual(received, n)
    }

    func upload(channel: EmbeddedChannel, length: Int, includeContentLength: Bool) throws {
        var head = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: "localhost:8888",
            path: "/responsiveness/upload"
        )
        if includeContentLength {
            head.headerFields[.contentLength] = "\(length)"
        }

        // Recv head
        try channel.writeInbound(HTTPRequestPart.head(head))

        // Shouldn't get any immediate response
        let out: HTTPResponsePart? = try channel.readOutbound()
        XCTAssertNil(out)

        // Send data
        var sent = 0
        while sent < length {
            let toWrite = min(length - sent, HTTPDrippingDownloadHandler.downloadBodyChunk.readableBytes)
            let buf = HTTPDrippingDownloadHandler.downloadBodyChunk.getSlice(
                at: HTTPDrippingDownloadHandler.downloadBodyChunk.readerIndex,
                length: toWrite
            )!
            try channel.writeInbound(HTTPRequestPart.body(buf))
            sent += toWrite
        }

        // Send fin
        try channel.writeInbound(HTTPRequestPart.end(nil))

        // Get response from server
        var part: HTTPResponsePart = (try channel.readOutbound())!
        guard case let HTTPResponsePart.head(head) = part else {
            XCTFail("expected response head")
            return
        }
        XCTAssertEqual(head.status, .ok)

        // Check response body to confirm server received everything we sent
        part = (try channel.readOutbound())!
        guard case let HTTPResponsePart.body(body) = part else {
            XCTFail("expected response body")
            return
        }
        XCTAssertEqual(String(buffer: body), "Received \(length) bytes")

        // Check server correctly closes the stream
        part = (try channel.readOutbound())!
        guard case HTTPResponsePart.end(nil) = part else {
            XCTFail("expected end")
            return
        }
    }

    func downloadOtherPath(channel: EmbeddedChannel, n: Int, expectFailue: Bool) throws {
        // The path "/other" is just an example, this can be any path not defined by the
        // responsiveness mux itself.
        try channel.writeInbound(
            HTTPRequestPart.head(
                HTTPRequest(
                    method: .get,
                    scheme: "http",
                    authority: "localhost:8888",
                    path: "/other/\(n)"
                )
            )
        )

        let out: HTTPResponsePart = (try channel.readOutbound())!
        guard case let HTTPResponsePart.head(head) = out else {
            XCTFail("expected response head")
            return
        }

        if expectFailue {
            // Should get 404 response
            XCTAssertEqual(head.status, .notFound)
        } else {
            // Should get response head with content length
            XCTAssertEqual(Int(head.headerFields[.contentLength]!)!, n)

            // Drain response body until completed
            var received = 0
            loop: while true {
                let out: HTTPResponsePart = (try channel.readOutbound())!
                switch out {
                case .head:
                    XCTFail("cannot get head twice")
                case .body(let body):
                    received += body.readableBytes
                case .end:
                    break loop
                }
            }
            XCTAssertEqual(received, n)
        }
    }

    private static let defaultValues = [0, 1, 2, 10, 1000, 20000]

    func testDownload() throws {
        for val in NIOHTTPResponsivenessTests.defaultValues {
            let channel = EmbeddedChannel(handler: HTTPDrippingDownloadHandler(count: 1, size: val))
            try download(channel: channel, n: val)
            let _ = try channel.finish()
        }
    }

    func testUpload() throws {
        for val in NIOHTTPResponsivenessTests.defaultValues {
            var channel = EmbeddedChannel(handler: HTTPReceiveDiscardHandler(expectation: val))
            try upload(channel: channel, length: val, includeContentLength: true)
            let _ = try channel.finish()

            channel = EmbeddedChannel(handler: HTTPReceiveDiscardHandler(expectation: nil))
            try upload(channel: channel, length: val, includeContentLength: false)
            let _ = try channel.finish()
        }
    }

    func testMuxDownload() throws {
        for val in NIOHTTPResponsivenessTests.defaultValues {
            let channel = EmbeddedChannel(
                handler: SimpleResponsivenessRequestMux(
                    responsivenessConfigBuffer: ByteBuffer(string: "test")
                )
            )
            try download(channel: channel, n: val)
            let _ = try channel.finish()
        }
    }

    func testMuxUpload() throws {
        for val in NIOHTTPResponsivenessTests.defaultValues {
            var channel = EmbeddedChannel(
                handler: SimpleResponsivenessRequestMux(
                    responsivenessConfigBuffer: ByteBuffer(string: "test")
                )
            )
            try upload(channel: channel, length: val, includeContentLength: true)
            let _ = try channel.finish()

            channel = EmbeddedChannel(
                handler: SimpleResponsivenessRequestMux(
                    responsivenessConfigBuffer: ByteBuffer(string: "test")
                )
            )
            try upload(channel: channel, length: val, includeContentLength: false)
            let _ = try channel.finish()
        }
    }

    func testRejectOther() throws {
        for val in NIOHTTPResponsivenessTests.defaultValues {
            let channel = EmbeddedChannel(
                handler: SimpleResponsivenessRequestMux(
                    responsivenessConfigBuffer: ByteBuffer(string: "test"),
                    forwardOtherRequests: false
                )
            )
            // Sending an unhandled path results in a 404 when not forwarding other requests.
            try downloadOtherPath(channel: channel, n: val, expectFailue: true)
            let _ = try channel.finish()
        }
    }

    func testMuxNoInterference() throws {
        for val in NIOHTTPResponsivenessTests.defaultValues {
            let channel = EmbeddedChannel(
                handler: SimpleResponsivenessRequestMux(
                    responsivenessConfigBuffer: ByteBuffer(string: "test"),
                    forwardOtherRequests: true
                )
            )
            // Add another handler to the channel pipeline
            try channel.pipeline.syncOperations.addHandler(HTTPDrippingDownloadHandler(count: 1, size: val))

            // An upload request is handled directly by the mux even with another handler added to the pipeline
            try upload(channel: channel, length: val, includeContentLength: true)
            let _ = try channel.finish()
        }
    }

    func testMuxForwardOther() throws {
        for val in NIOHTTPResponsivenessTests.defaultValues {
            let channel = EmbeddedChannel(
                handler: SimpleResponsivenessRequestMux(
                    responsivenessConfigBuffer: ByteBuffer(string: "test"),
                    forwardOtherRequests: true
                )
            )
            // Add another handler to the channel pipeline
            try channel.pipeline.syncOperations.addHandler(HTTPDrippingDownloadHandler(count: 1, size: val))

            // A request that is not handled by the mux itself is forwarded to the handler added to pipeline
            try downloadOtherPath(channel: channel, n: val, expectFailue: false)
            let _ = try channel.finish()
        }
    }
}
