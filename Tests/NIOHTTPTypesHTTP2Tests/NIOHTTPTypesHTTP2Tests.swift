//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftNIO project authors
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
import NIOHPACK
import NIOHTTP2
import NIOHTTPTypes
import NIOHTTPTypesHTTP2
import XCTest

/// A handler that keeps track of all reads made on a channel.
private final class InboundRecorder<Frame>: ChannelInboundHandler {
    typealias InboundIn = Frame

    var receivedFrames: [Frame] = []

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.receivedFrames.append(self.unwrapInboundIn(data))
    }
}

extension HTTPField.Name {
    static let xFoo = Self("X-Foo")!
}

extension HTTP2Frame.FramePayload {
    var headers: HPACKHeaders? {
        if case .headers(let headers) = self {
            return headers.headers
        } else {
            return nil
        }
    }

    init(headers: HPACKHeaders) {
        self = .headers(.init(headers: headers))
    }
}

final class NIOHTTPTypesHTTP2Tests: XCTestCase {
    var channel: EmbeddedChannel!

    override func setUp() {
        super.setUp()
        self.channel = EmbeddedChannel()
    }

    override func tearDown() {
        self.channel = nil
        super.tearDown()
    }

    static let request = HTTPRequest(
        method: .get,
        scheme: "https",
        authority: "www.example.com",
        path: "/",
        headerFields: [
            .accept: "*/*",
            .acceptEncoding: "gzip",
            .acceptEncoding: "br",
            .trailer: "X-Foo",
            .cookie: "a=b",
            .cookie: "c=d",
        ]
    )

    static let oldRequest: HPACKHeaders = [
        ":method": "GET",
        ":scheme": "https",
        ":authority": "www.example.com",
        ":path": "/",
        "accept": "*/*",
        "accept-encoding": "gzip",
        "accept-encoding": "br",
        "trailer": "X-Foo",
        "cookie": "a=b",
        "cookie": "c=d",
    ]

    static let response = HTTPResponse(
        status: .ok,
        headerFields: [
            .server: "HTTPServer/1.0",
            .trailer: "X-Foo",
        ]
    )

    static let oldResponse: HPACKHeaders = [
        ":status": "200",
        "server": "HTTPServer/1.0",
        "trailer": "X-Foo",
    ]

    static let trailers: HTTPFields = [.xFoo: "Bar"]

    static let oldTrailers: HPACKHeaders = ["x-foo": "Bar"]

    func testClientHTTP2ToHTTP() throws {
        let recorder = InboundRecorder<HTTPResponsePart>()

        try self.channel.pipeline.syncOperations.addHandlers(HTTP2FramePayloadToHTTPClientCodec(), recorder)

        try self.channel.writeOutbound(HTTPRequestPart.head(Self.request))
        try self.channel.writeOutbound(HTTPRequestPart.end(Self.trailers))
        try self.channel.triggerUserOutboundEvent(NIOHTTP2FramePayloadToHTTPEvent.reset(code: .enhanceYourCalm)).wait()

        XCTAssertEqual(try self.channel.readOutbound(as: HTTP2Frame.FramePayload.self)?.headers, Self.oldRequest)
        XCTAssertEqual(try self.channel.readOutbound(as: HTTP2Frame.FramePayload.self)?.headers, Self.oldTrailers)
        switch try self.channel.readOutbound(as: HTTP2Frame.FramePayload.self) {
        case .rstStream(.enhanceYourCalm):
            break
        default:
            XCTFail("expected reset")
        }

        try self.channel.writeInbound(HTTP2Frame.FramePayload(headers: Self.oldResponse))
        try self.channel.writeInbound(HTTP2Frame.FramePayload(headers: Self.oldTrailers))

        XCTAssertEqual(recorder.receivedFrames[0], .head(Self.response))
        XCTAssertEqual(recorder.receivedFrames[1], .end(Self.trailers))

        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testServerHTTP2ToHTTP() throws {
        let recorder = InboundRecorder<HTTPRequestPart>()

        try self.channel.pipeline.syncOperations.addHandlers(HTTP2FramePayloadToHTTPServerCodec(), recorder)

        try self.channel.writeInbound(HTTP2Frame.FramePayload(headers: Self.oldRequest))
        try self.channel.writeInbound(HTTP2Frame.FramePayload(headers: Self.oldTrailers))

        XCTAssertEqual(recorder.receivedFrames[0], .head(Self.request))
        XCTAssertEqual(recorder.receivedFrames[1], .end(Self.trailers))

        try self.channel.writeOutbound(HTTPResponsePart.head(Self.response))
        try self.channel.writeOutbound(HTTPResponsePart.end(Self.trailers))
        try self.channel.triggerUserOutboundEvent(NIOHTTP2FramePayloadToHTTPEvent.reset(code: .enhanceYourCalm)).wait()

        XCTAssertEqual(try self.channel.readOutbound(as: HTTP2Frame.FramePayload.self)?.headers, Self.oldResponse)
        XCTAssertEqual(try self.channel.readOutbound(as: HTTP2Frame.FramePayload.self)?.headers, Self.oldTrailers)
        switch try self.channel.readOutbound(as: HTTP2Frame.FramePayload.self) {
        case .rstStream(.enhanceYourCalm):
            break
        default:
            XCTFail("expected reset")
        }

        XCTAssertTrue(try self.channel.finish().isClean)
    }
}
