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
import NIOHTTPTypes
import NIOResumableUpload
import XCTest

/// A handler that keeps track of all reads made on a channel.
private final class InboundRecorder<Frame>: ChannelInboundHandler {
    typealias InboundIn = Frame

    var receivedFrames: [Frame] = []

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.receivedFrames.append(self.unwrapInboundIn(data))
    }
}

final class NIOResumableUploadTests: XCTestCase {
    func testNonUpload() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.addHandler(HTTPResumableUploadHandler(context: context, handlers: [recorder])).wait()

        let request = HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/")
        try channel.writeInbound(HTTPRequestPart.head(request))
        try channel.writeInbound(HTTPRequestPart.end(nil))

        XCTAssertEqual(recorder.receivedFrames.count, 2)
        XCTAssertEqual(recorder.receivedFrames[0], HTTPRequestPart.head(request))
        XCTAssertEqual(recorder.receivedFrames[1], HTTPRequestPart.end(nil))
        XCTAssertTrue(try channel.finish().isClean)
    }

    func testNotResumableUpload() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.addHandler(HTTPResumableUploadHandler(context: context, handlers: [recorder])).wait()

        let request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        try channel.writeInbound(HTTPRequestPart.head(request))
        try channel.writeInbound(HTTPRequestPart.body(ByteBuffer(string: "Hello")))
        try channel.writeInbound(HTTPRequestPart.end(nil))

        XCTAssertEqual(recorder.receivedFrames.count, 3)
        XCTAssertEqual(recorder.receivedFrames[0], HTTPRequestPart.head(request))
        XCTAssertEqual(recorder.receivedFrames[1], HTTPRequestPart.body(ByteBuffer(string: "Hello")))
        XCTAssertEqual(recorder.receivedFrames[2], HTTPRequestPart.end(nil))
        XCTAssertTrue(try channel.finish().isClean)
    }

    func testResumableUploadUninterrupted() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.addHandler(HTTPResumableUploadHandler(context: context, handlers: [recorder])).wait()

        var request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        request.headerFields[.uploadDraftInteropVersion] = "3"
        request.headerFields[.uploadIncomplete] = "?0"
        request.headerFields[.contentLength] = "5"
        try channel.writeInbound(HTTPRequestPart.head(request))
        try channel.writeInbound(HTTPRequestPart.body(ByteBuffer(string: "Hello")))
        try channel.writeInbound(HTTPRequestPart.end(nil))

        XCTAssertEqual(recorder.receivedFrames.count, 3)
        var expectedRequest = request
        expectedRequest.headerFields[.uploadIncomplete] = nil
        XCTAssertEqual(recorder.receivedFrames[0], HTTPRequestPart.head(expectedRequest))
        XCTAssertEqual(recorder.receivedFrames[1], HTTPRequestPart.body(ByteBuffer(string: "Hello")))
        XCTAssertEqual(recorder.receivedFrames[2], HTTPRequestPart.end(nil))

        let responsePart = try channel.readOutbound(as: HTTPResponsePart.self)
        guard case .head(let response) = responsePart else {
            XCTFail("Part is not response headers")
            return
        }
        XCTAssertEqual(response.status.code, 104)
        XCTAssertNotNil(response.headerFields[.location])
        XCTAssertTrue(try channel.finish().isClean)
    }

    func testResumableUploadInterrupted() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.addHandler(HTTPResumableUploadHandler(context: context, handlers: [recorder])).wait()

        var request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        request.headerFields[.uploadDraftInteropVersion] = "3"
        request.headerFields[.uploadIncomplete] = "?0"
        request.headerFields[.contentLength] = "5"
        try channel.writeInbound(HTTPRequestPart.head(request))
        try channel.writeInbound(HTTPRequestPart.body(ByteBuffer(string: "He")))
        channel.pipeline.fireErrorCaught(POSIXError(.ENOTCONN))

        let responsePart = try channel.readOutbound(as: HTTPResponsePart.self)
        guard case .head(let response) = responsePart else {
            XCTFail("Part is not response headers")
            return
        }
        XCTAssertEqual(response.status.code, 104)
        let location = try XCTUnwrap(response.headerFields[.location])
        let resumptionPath = try XCTUnwrap(URLComponents(string: location)?.path)

        let channel2 = EmbeddedChannel()
        try channel2.pipeline.addHandler(HTTPResumableUploadHandler(context: context, handlers: [])).wait()
        var request2 = HTTPRequest(method: .head, scheme: "https", authority: "example.com", path: resumptionPath)
        request2.headerFields[.uploadDraftInteropVersion] = "3"
        try channel2.writeInbound(HTTPRequestPart.head(request2))
        try channel2.writeInbound(HTTPRequestPart.end(nil))
        let responsePart2 = try channel2.readOutbound(as: HTTPResponsePart.self)
        guard case .head(let response2) = responsePart2 else {
            XCTFail("Part is not response headers")
            return
        }
        XCTAssertEqual(response2.status.code, 204)
        XCTAssertEqual(response2.headerFields[.uploadOffset], "2")
        XCTAssertEqual(try channel2.readOutbound(as: HTTPResponsePart.self), .end(nil))
        XCTAssertTrue(try channel2.finish().isClean)

        let channel3 = EmbeddedChannel()
        try channel3.pipeline.addHandler(HTTPResumableUploadHandler(context: context, handlers: [])).wait()
        var request3 = HTTPRequest(method: .patch, scheme: "https", authority: "example.com", path: resumptionPath)
        request3.headerFields[.uploadDraftInteropVersion] = "3"
        request3.headerFields[.uploadIncomplete] = "?0"
        request3.headerFields[.uploadOffset] = "2"
        request3.headerFields[.contentLength] = "3"
        try channel3.writeInbound(HTTPRequestPart.head(request3))
        try channel3.writeInbound(HTTPRequestPart.body(ByteBuffer(string: "llo")))
        try channel3.writeInbound(HTTPRequestPart.end(nil))

        XCTAssertEqual(recorder.receivedFrames.count, 4)
        var expectedRequest = request
        expectedRequest.headerFields[.uploadIncomplete] = nil
        XCTAssertEqual(recorder.receivedFrames[0], HTTPRequestPart.head(expectedRequest))
        XCTAssertEqual(recorder.receivedFrames[1], HTTPRequestPart.body(ByteBuffer(string: "He")))
        XCTAssertEqual(recorder.receivedFrames[2], HTTPRequestPart.body(ByteBuffer(string: "llo")))
        XCTAssertEqual(recorder.receivedFrames[3], HTTPRequestPart.end(nil))
        XCTAssertTrue(try channel3.finish().isClean)
        XCTAssertTrue(try channel.finish().isClean)
    }

    func testResumableUploadChunked() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.addHandler(HTTPResumableUploadHandler(context: context, handlers: [recorder])).wait()

        var request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        request.headerFields[.uploadDraftInteropVersion] = "3"
        request.headerFields[.uploadIncomplete] = "?1"
        request.headerFields[.contentLength] = "2"
        try channel.writeInbound(HTTPRequestPart.head(request))
        try channel.writeInbound(HTTPRequestPart.body(ByteBuffer(string: "He")))
        try channel.writeInbound(HTTPRequestPart.end(nil))

        let responsePart = try channel.readOutbound(as: HTTPResponsePart.self)
        guard case .head(let response) = responsePart else {
            XCTFail("Part is not response headers")
            return
        }
        XCTAssertEqual(response.status.code, 104)
        let location = try XCTUnwrap(response.headerFields[.location])
        let resumptionPath = try XCTUnwrap(URLComponents(string: location)?.path)

        let finalResponsePart = try channel.readOutbound(as: HTTPResponsePart.self)
        guard case .head(let finalResponse) = finalResponsePart else {
            XCTFail("Part is not final response headers")
            return
        }
        XCTAssertEqual(finalResponse.status.code, 201)
        XCTAssertEqual(try channel.readOutbound(as: HTTPResponsePart.self), .end(nil))

        let channel2 = EmbeddedChannel()
        try channel2.pipeline.addHandler(HTTPResumableUploadHandler(context: context, handlers: [])).wait()
        var request2 = HTTPRequest(method: .head, scheme: "https", authority: "example.com", path: resumptionPath)
        request2.headerFields[.uploadDraftInteropVersion] = "3"
        try channel2.writeInbound(HTTPRequestPart.head(request2))
        try channel2.writeInbound(HTTPRequestPart.end(nil))
        let responsePart2 = try channel2.readOutbound(as: HTTPResponsePart.self)
        guard case .head(let response2) = responsePart2 else {
            XCTFail("Part is not response headers")
            return
        }
        XCTAssertEqual(response2.status.code, 204)
        XCTAssertEqual(response2.headerFields[.uploadOffset], "2")
        XCTAssertEqual(try channel2.readOutbound(as: HTTPResponsePart.self), .end(nil))
        XCTAssertTrue(try channel2.finish().isClean)

        let channel3 = EmbeddedChannel()
        try channel3.pipeline.addHandler(HTTPResumableUploadHandler(context: context, handlers: [])).wait()
        var request3 = HTTPRequest(method: .patch, scheme: "https", authority: "example.com", path: resumptionPath)
        request3.headerFields[.uploadDraftInteropVersion] = "3"
        request3.headerFields[.uploadIncomplete] = "?0"
        request3.headerFields[.uploadOffset] = "2"
        request3.headerFields[.contentLength] = "3"
        try channel3.writeInbound(HTTPRequestPart.head(request3))
        try channel3.writeInbound(HTTPRequestPart.body(ByteBuffer(string: "llo")))
        try channel3.writeInbound(HTTPRequestPart.end(nil))

        XCTAssertEqual(recorder.receivedFrames.count, 4)
        var expectedRequest = request
        expectedRequest.headerFields[.uploadIncomplete] = nil
        XCTAssertEqual(recorder.receivedFrames[0], HTTPRequestPart.head(expectedRequest))
        XCTAssertEqual(recorder.receivedFrames[1], HTTPRequestPart.body(ByteBuffer(string: "He")))
        XCTAssertEqual(recorder.receivedFrames[2], HTTPRequestPart.body(ByteBuffer(string: "llo")))
        XCTAssertEqual(recorder.receivedFrames[3], HTTPRequestPart.end(nil))
        XCTAssertTrue(try channel3.finish().isClean)
        XCTAssertTrue(try channel.finish().isClean)
    }
}

extension HTTPField.Name {
    fileprivate static let uploadDraftInteropVersion = Self("Upload-Draft-Interop-Version")!
    fileprivate static let uploadIncomplete = Self("Upload-Incomplete")!
    fileprivate static let uploadOffset = Self("Upload-Offset")!
}
