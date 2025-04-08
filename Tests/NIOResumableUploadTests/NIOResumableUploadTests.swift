//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the SwiftNIO project authors
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
private final class InboundRecorder<FrameIn, FrameOut>: ChannelDuplexHandler {
    typealias InboundIn = FrameIn
    typealias OutboundIn = Never
    typealias OutboundOut = FrameOut

    private var context: ChannelHandlerContext! = nil

    var receivedFrames: [FrameIn] = []

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.receivedFrames.append(self.unwrapInboundIn(data))
    }

    func write(_ frame: FrameOut) {
        self.write(context: self.context, data: self.wrapOutboundOut(frame), promise: nil)
        self.flush(context: self.context)
    }
}

final class NIOResumableUploadTests: XCTestCase {
    func testNonUpload() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart, Never>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.syncOperations.addHandler(
            HTTPResumableUploadHandler(context: context, handlers: [recorder])
        )

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
        let recorder = InboundRecorder<HTTPRequestPart, Never>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.syncOperations.addHandler(
            HTTPResumableUploadHandler(context: context, handlers: [recorder])
        )

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

    func testOptions() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart, HTTPResponsePart>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.syncOperations.addHandler(
            HTTPResumableUploadHandler(context: context, handlers: [recorder])
        )

        var request = HTTPRequest(method: .options, scheme: "https", authority: "example.com", path: "/")
        request.headerFields[.uploadDraftInteropVersion] = "6"
        try channel.writeInbound(HTTPRequestPart.head(request))
        try channel.writeInbound(HTTPRequestPart.end(nil))

        XCTAssertEqual(recorder.receivedFrames.count, 2)
        XCTAssertEqual(recorder.receivedFrames[0], HTTPRequestPart.head(request))
        XCTAssertEqual(recorder.receivedFrames[1], HTTPRequestPart.end(nil))

        recorder.write(HTTPResponsePart.head(HTTPResponse(status: .notImplemented)))
        recorder.write(HTTPResponsePart.end(nil))

        let responsePart = try channel.readOutbound(as: HTTPResponsePart.self)
        guard case .head(let response) = responsePart else {
            XCTFail("Part is not response headers")
            return
        }
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.headerFields[.uploadLimit], "min-size=0")
        guard let responsePart = try channel.readOutbound(as: HTTPResponsePart.self), case .end = responsePart else {
            XCTFail("Part is not response end")
            return
        }
        XCTAssertTrue(try channel.finish().isClean)
    }

    func testResumableUploadUninterruptedV3() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart, Never>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.syncOperations.addHandler(
            HTTPResumableUploadHandler(context: context, handlers: [recorder])
        )

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

    func testResumableUploadUninterruptedV5() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart, Never>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.syncOperations.addHandler(
            HTTPResumableUploadHandler(context: context, handlers: [recorder])
        )

        var request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        request.headerFields[.uploadDraftInteropVersion] = "5"
        request.headerFields[.uploadComplete] = "?1"
        request.headerFields[.contentLength] = "5"
        try channel.writeInbound(HTTPRequestPart.head(request))
        try channel.writeInbound(HTTPRequestPart.body(ByteBuffer(string: "Hello")))
        try channel.writeInbound(HTTPRequestPart.end(nil))

        XCTAssertEqual(recorder.receivedFrames.count, 3)
        var expectedRequest = request
        expectedRequest.headerFields[.uploadComplete] = nil
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

    func testResumableUploadUninterruptedV6() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart, Never>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.syncOperations.addHandler(
            HTTPResumableUploadHandler(context: context, handlers: [recorder])
        )

        var request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        request.headerFields[.uploadDraftInteropVersion] = "6"
        request.headerFields[.uploadComplete] = "?1"
        request.headerFields[.contentLength] = "5"
        request.headerFields[.uploadLength] = "5"
        try channel.writeInbound(HTTPRequestPart.head(request))
        try channel.writeInbound(HTTPRequestPart.body(ByteBuffer(string: "Hello")))
        try channel.writeInbound(HTTPRequestPart.end(nil))

        XCTAssertEqual(recorder.receivedFrames.count, 3)
        var expectedRequest = request
        expectedRequest.headerFields[.uploadComplete] = nil
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

    func testResumableUploadInterruptedV3() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart, Never>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.syncOperations.addHandler(
            HTTPResumableUploadHandler(context: context, handlers: [recorder])
        )

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
        try channel2.pipeline.syncOperations.addHandler(HTTPResumableUploadHandler(context: context, handlers: []))
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
        try channel3.pipeline.syncOperations.addHandler(HTTPResumableUploadHandler(context: context, handlers: []))
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

    func testResumableUploadInterruptedV5() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart, Never>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.syncOperations.addHandler(
            HTTPResumableUploadHandler(context: context, handlers: [recorder])
        )

        var request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        request.headerFields[.uploadDraftInteropVersion] = "5"
        request.headerFields[.uploadComplete] = "?1"
        request.headerFields[.contentLength] = "5"
        request.headerFields[.uploadLength] = "5"
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
        try channel2.pipeline.syncOperations.addHandler(HTTPResumableUploadHandler(context: context, handlers: []))
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
        try channel3.pipeline.syncOperations.addHandler(HTTPResumableUploadHandler(context: context, handlers: []))
        var request3 = HTTPRequest(method: .patch, scheme: "https", authority: "example.com", path: resumptionPath)
        request3.headerFields[.uploadDraftInteropVersion] = "5"
        request3.headerFields[.uploadComplete] = "?1"
        request3.headerFields[.uploadOffset] = "2"
        request3.headerFields[.contentLength] = "3"
        request3.headerFields[.uploadLength] = "5"
        try channel3.writeInbound(HTTPRequestPart.head(request3))
        try channel3.writeInbound(HTTPRequestPart.body(ByteBuffer(string: "llo")))
        try channel3.writeInbound(HTTPRequestPart.end(nil))

        XCTAssertEqual(recorder.receivedFrames.count, 4)
        var expectedRequest = request
        expectedRequest.headerFields[.uploadComplete] = nil
        XCTAssertEqual(recorder.receivedFrames[0], HTTPRequestPart.head(expectedRequest))
        XCTAssertEqual(recorder.receivedFrames[1], HTTPRequestPart.body(ByteBuffer(string: "He")))
        XCTAssertEqual(recorder.receivedFrames[2], HTTPRequestPart.body(ByteBuffer(string: "llo")))
        XCTAssertEqual(recorder.receivedFrames[3], HTTPRequestPart.end(nil))
        XCTAssertTrue(try channel3.finish().isClean)
        XCTAssertTrue(try channel.finish().isClean)
    }

    func testResumableUploadInterruptedV6() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart, Never>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.syncOperations.addHandler(
            HTTPResumableUploadHandler(context: context, handlers: [recorder])
        )

        var request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        request.headerFields[.uploadDraftInteropVersion] = "6"
        request.headerFields[.uploadComplete] = "?1"
        request.headerFields[.contentLength] = "5"
        request.headerFields[.uploadLength] = "5"
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
        try channel2.pipeline.syncOperations.addHandler(HTTPResumableUploadHandler(context: context, handlers: []))
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
        try channel3.pipeline.syncOperations.addHandler(HTTPResumableUploadHandler(context: context, handlers: []))
        var request3 = HTTPRequest(method: .patch, scheme: "https", authority: "example.com", path: resumptionPath)
        request3.headerFields[.uploadDraftInteropVersion] = "6"
        request3.headerFields[.uploadComplete] = "?1"
        request3.headerFields[.uploadOffset] = "2"
        request3.headerFields[.contentLength] = "3"
        request3.headerFields[.uploadLength] = "5"
        request3.headerFields[.contentType] = "application/partial-upload"
        try channel3.writeInbound(HTTPRequestPart.head(request3))
        try channel3.writeInbound(HTTPRequestPart.body(ByteBuffer(string: "llo")))
        try channel3.writeInbound(HTTPRequestPart.end(nil))

        XCTAssertEqual(recorder.receivedFrames.count, 4)
        var expectedRequest = request
        expectedRequest.headerFields[.uploadComplete] = nil
        XCTAssertEqual(recorder.receivedFrames[0], HTTPRequestPart.head(expectedRequest))
        XCTAssertEqual(recorder.receivedFrames[1], HTTPRequestPart.body(ByteBuffer(string: "He")))
        XCTAssertEqual(recorder.receivedFrames[2], HTTPRequestPart.body(ByteBuffer(string: "llo")))
        XCTAssertEqual(recorder.receivedFrames[3], HTTPRequestPart.end(nil))
        XCTAssertTrue(try channel3.finish().isClean)
        XCTAssertTrue(try channel.finish().isClean)
    }

    func testResumableUploadChunkedV3() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart, Never>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.syncOperations.addHandler(
            HTTPResumableUploadHandler(context: context, handlers: [recorder])
        )

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
        try channel2.pipeline.syncOperations.addHandler(HTTPResumableUploadHandler(context: context, handlers: []))
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
        try channel3.pipeline.syncOperations.addHandler(HTTPResumableUploadHandler(context: context, handlers: []))
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

    func testResumableUploadChunkedV5() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart, Never>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.syncOperations.addHandler(
            HTTPResumableUploadHandler(context: context, handlers: [recorder])
        )

        var request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        request.headerFields[.uploadDraftInteropVersion] = "5"
        request.headerFields[.uploadComplete] = "?0"
        request.headerFields[.contentLength] = "2"
        request.headerFields[.uploadLength] = "5"
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
        try channel2.pipeline.syncOperations.addHandler(HTTPResumableUploadHandler(context: context, handlers: []))
        var request2 = HTTPRequest(method: .head, scheme: "https", authority: "example.com", path: resumptionPath)
        request2.headerFields[.uploadDraftInteropVersion] = "5"
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
        try channel3.pipeline.syncOperations.addHandler(HTTPResumableUploadHandler(context: context, handlers: []))
        var request3 = HTTPRequest(method: .patch, scheme: "https", authority: "example.com", path: resumptionPath)
        request3.headerFields[.uploadDraftInteropVersion] = "5"
        request3.headerFields[.uploadComplete] = "?1"
        request3.headerFields[.uploadOffset] = "2"
        request3.headerFields[.contentLength] = "3"
        request3.headerFields[.uploadLength] = "5"
        try channel3.writeInbound(HTTPRequestPart.head(request3))
        try channel3.writeInbound(HTTPRequestPart.body(ByteBuffer(string: "llo")))
        try channel3.writeInbound(HTTPRequestPart.end(nil))

        XCTAssertEqual(recorder.receivedFrames.count, 4)
        var expectedRequest = request
        expectedRequest.headerFields[.uploadComplete] = nil
        XCTAssertEqual(recorder.receivedFrames[0], HTTPRequestPart.head(expectedRequest))
        XCTAssertEqual(recorder.receivedFrames[1], HTTPRequestPart.body(ByteBuffer(string: "He")))
        XCTAssertEqual(recorder.receivedFrames[2], HTTPRequestPart.body(ByteBuffer(string: "llo")))
        XCTAssertEqual(recorder.receivedFrames[3], HTTPRequestPart.end(nil))
        XCTAssertTrue(try channel3.finish().isClean)
        XCTAssertTrue(try channel.finish().isClean)
    }

    func testResumableUploadChunkedV6() throws {
        let channel = EmbeddedChannel()
        let recorder = InboundRecorder<HTTPRequestPart, Never>()

        let context = HTTPResumableUploadContext(origin: "https://example.com")
        try channel.pipeline.syncOperations.addHandler(
            HTTPResumableUploadHandler(context: context, handlers: [recorder])
        )

        var request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        request.headerFields[.uploadDraftInteropVersion] = "6"
        request.headerFields[.uploadComplete] = "?0"
        request.headerFields[.contentLength] = "2"
        request.headerFields[.uploadLength] = "5"
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
        try channel2.pipeline.syncOperations.addHandler(HTTPResumableUploadHandler(context: context, handlers: []))
        var request2 = HTTPRequest(method: .head, scheme: "https", authority: "example.com", path: resumptionPath)
        request2.headerFields[.uploadDraftInteropVersion] = "6"
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
        try channel3.pipeline.syncOperations.addHandler(HTTPResumableUploadHandler(context: context, handlers: []))
        var request3 = HTTPRequest(method: .patch, scheme: "https", authority: "example.com", path: resumptionPath)
        request3.headerFields[.uploadDraftInteropVersion] = "6"
        request3.headerFields[.uploadComplete] = "?1"
        request3.headerFields[.uploadOffset] = "2"
        request3.headerFields[.contentLength] = "3"
        request3.headerFields[.uploadLength] = "5"
        request3.headerFields[.contentType] = "application/partial-upload"
        try channel3.writeInbound(HTTPRequestPart.head(request3))
        try channel3.writeInbound(HTTPRequestPart.body(ByteBuffer(string: "llo")))
        try channel3.writeInbound(HTTPRequestPart.end(nil))

        XCTAssertEqual(recorder.receivedFrames.count, 4)
        var expectedRequest = request
        expectedRequest.headerFields[.uploadComplete] = nil
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
    fileprivate static let uploadComplete = Self("Upload-Complete")!
    fileprivate static let uploadIncomplete = Self("Upload-Incomplete")!
    fileprivate static let uploadOffset = Self("Upload-Offset")!
    fileprivate static let uploadLength = Self("Upload-Length")!
    fileprivate static let uploadLimit = Self("Upload-Limit")!
}
