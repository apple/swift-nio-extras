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
import NIOHTTP1
import NIOHTTPTypes
import NIOHTTPTypesHTTP1
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

final class NIOHTTPTypesHTTP1Tests: XCTestCase {
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
        path: "/path?query=1",
        headerFields: [
            .accept: "*/*",
            .acceptEncoding: "gzip",
            .acceptEncoding: "br",
            .cookie: "a=b",
            .cookie: "c=d",
            .trailer: "X-Foo",
        ]
    )

    static let requestNoSplitCookie = HTTPRequest(
        method: .get,
        scheme: "https",
        authority: "www.example.com",
        path: "/path?query=1",
        headerFields: [
            .accept: "*/*",
            .acceptEncoding: "gzip",
            .acceptEncoding: "br",
            .cookie: "a=b; c=d",
            .trailer: "X-Foo",
        ]
    )

    static let oldRequest = HTTPRequestHead(
        version: .http1_1,
        method: .GET,
        uri: "/path?query=1",
        headers: [
            "Host": "www.example.com",
            "Accept": "*/*",
            "Accept-Encoding": "gzip",
            "Accept-Encoding": "br",
            "Cookie": "a=b; c=d",
            "Trailer": "X-Foo",
        ]
    )

    static let oldRequestAbsolute = HTTPRequestHead(
        version: .http1_1,
        method: .GET,
        uri: "https://www.example.com/path?query=1",
        headers: [
            "Host": "www.example.com",
            "Accept": "*/*",
            "Accept-Encoding": "gzip",
            "Accept-Encoding": "br",
            "Cookie": "a=b; c=d",
            "Trailer": "X-Foo",
        ]
    )

    static let response = HTTPResponse(
        status: .ok,
        headerFields: [
            .server: "HTTPServer/1.0",
            .trailer: "X-Foo",
        ]
    )

    static let oldResponse = HTTPResponseHead(
        version: .http1_1,
        status: .ok,
        headers: [
            "Server": "HTTPServer/1.0",
            "Trailer": "X-Foo",
        ]
    )

    static let trailers: HTTPFields = [.xFoo: "Bar"]

    static let oldTrailers: HTTPHeaders = ["X-Foo": "Bar"]

    func testClientHTTP1ToHTTP() throws {
        let recorder = InboundRecorder<HTTPResponsePart>()

        try self.channel.pipeline.syncOperations.addHandlers(HTTP1ToHTTPClientCodec(), recorder)

        try self.channel.writeOutbound(HTTPRequestPart.head(Self.request))
        try self.channel.writeOutbound(HTTPRequestPart.end(Self.trailers))

        XCTAssertEqual(try self.channel.readOutbound(as: HTTPClientRequestPart.self), .head(Self.oldRequest))
        XCTAssertEqual(try self.channel.readOutbound(as: HTTPClientRequestPart.self), .end(Self.oldTrailers))

        try self.channel.writeInbound(HTTPClientResponsePart.head(Self.oldResponse))
        try self.channel.writeInbound(HTTPClientResponsePart.end(Self.oldTrailers))

        XCTAssertEqual(recorder.receivedFrames[0], .head(Self.response))
        XCTAssertEqual(recorder.receivedFrames[1], .end(Self.trailers))

        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testServerHTTP1ToHTTP() throws {
        let recorder = InboundRecorder<HTTPRequestPart>()

        try self.channel.pipeline.syncOperations.addHandlers(HTTP1ToHTTPServerCodec(secure: true), recorder)

        try self.channel.writeInbound(HTTPServerRequestPart.head(Self.oldRequest))
        try self.channel.writeInbound(HTTPServerRequestPart.end(Self.oldTrailers))

        XCTAssertEqual(recorder.receivedFrames[0], .head(Self.requestNoSplitCookie))
        XCTAssertEqual(recorder.receivedFrames[1], .end(Self.trailers))

        try self.channel.writeOutbound(HTTPResponsePart.head(Self.response))
        try self.channel.writeOutbound(HTTPResponsePart.end(Self.trailers))

        XCTAssertEqual(try self.channel.readOutbound(as: HTTPServerResponsePart.self), .head(Self.oldResponse))
        XCTAssertEqual(try self.channel.readOutbound(as: HTTPServerResponsePart.self), .end(Self.oldTrailers))

        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testClientHTTPToHTTP1() throws {
        let recorder = InboundRecorder<HTTPClientResponsePart>()

        try self.channel.pipeline.syncOperations.addHandlers(HTTPToHTTP1ClientCodec(secure: true), recorder)

        try self.channel.writeOutbound(HTTPClientRequestPart.head(Self.oldRequest))
        try self.channel.writeOutbound(HTTPClientRequestPart.end(Self.oldTrailers))

        XCTAssertEqual(try self.channel.readOutbound(as: HTTPRequestPart.self), .head(Self.request))
        XCTAssertEqual(try self.channel.readOutbound(as: HTTPRequestPart.self), .end(Self.trailers))

        try self.channel.writeInbound(HTTPResponsePart.head(Self.response))
        try self.channel.writeInbound(HTTPResponsePart.end(Self.trailers))

        XCTAssertEqual(recorder.receivedFrames[0], .head(Self.oldResponse))
        XCTAssertEqual(recorder.receivedFrames[1], .end(Self.oldTrailers))

        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testServerHTTPToHTTP1() throws {
        let recorder = InboundRecorder<HTTPServerRequestPart>()

        try self.channel.pipeline.syncOperations.addHandlers(HTTPToHTTP1ServerCodec(), recorder)

        try self.channel.writeInbound(HTTPRequestPart.head(Self.request))
        try self.channel.writeInbound(HTTPRequestPart.end(Self.trailers))

        XCTAssertEqual(recorder.receivedFrames[0], .head(Self.oldRequest))
        XCTAssertEqual(recorder.receivedFrames[1], .end(Self.oldTrailers))

        try self.channel.writeOutbound(HTTPServerResponsePart.head(Self.oldResponse))
        try self.channel.writeOutbound(HTTPServerResponsePart.end(Self.oldTrailers))

        XCTAssertEqual(try self.channel.readOutbound(as: HTTPResponsePart.self), .head(Self.response))
        XCTAssertEqual(try self.channel.readOutbound(as: HTTPResponsePart.self), .end(Self.trailers))

        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testClientHTTP1ToHTTPAbsolute() throws {
        let recorder = InboundRecorder<HTTPResponsePart>()

        try self.channel.pipeline.syncOperations.addHandlers(HTTP1ToHTTPClientCodec(absoluteForm: true), recorder)

        try self.channel.writeOutbound(HTTPRequestPart.head(Self.request))

        XCTAssertEqual(try self.channel.readOutbound(as: HTTPClientRequestPart.self), .head(Self.oldRequestAbsolute))
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testServerHTTP1ToHTTPAbsolute() throws {
        let recorder = InboundRecorder<HTTPRequestPart>()

        try self.channel.pipeline.syncOperations.addHandlers(HTTP1ToHTTPServerCodec(secure: true), recorder)

        try self.channel.writeInbound(HTTPServerRequestPart.head(Self.oldRequestAbsolute))

        XCTAssertEqual(recorder.receivedFrames[0], .head(Self.requestNoSplitCookie))
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testClientHTTPToHTTP1Absolute() throws {
        let recorder = InboundRecorder<HTTPClientResponsePart>()

        try self.channel.pipeline.syncOperations.addHandlers(HTTPToHTTP1ClientCodec(secure: true), recorder)

        try self.channel.writeOutbound(HTTPClientRequestPart.head(Self.oldRequestAbsolute))

        XCTAssertEqual(try self.channel.readOutbound(as: HTTPRequestPart.self), .head(Self.request))
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testServerHTTPToHTTP1Absolute() throws {
        let recorder = InboundRecorder<HTTPServerRequestPart>()

        try self.channel.pipeline.syncOperations.addHandlers(HTTPToHTTP1ServerCodec(absoluteForm: true), recorder)

        try self.channel.writeInbound(HTTPRequestPart.head(Self.request))

        XCTAssertEqual(recorder.receivedFrames[0], .head(Self.oldRequestAbsolute))
        XCTAssertTrue(try self.channel.finish().isClean)
    }
}
