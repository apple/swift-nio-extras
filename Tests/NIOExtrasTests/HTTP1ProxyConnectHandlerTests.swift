//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2022 Apple Inc. and the SwiftNIO project authors
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
import NIOHTTP1
import XCTest

@testable import NIOExtras

class HTTP1ProxyConnectHandlerTests: XCTestCase {
    func testProxyConnectWithoutAuthorizationSuccess() throws {
        let embedded = EmbeddedChannel()
        defer { XCTAssertNoThrow(try embedded.finish(acceptAlreadyClosed: false)) }

        let socketAddress = try! SocketAddress.makeAddressResolvingHost("localhost", port: 0)
        XCTAssertNoThrow(try embedded.connect(to: socketAddress).wait())

        let promise: EventLoopPromise<Void> = embedded.eventLoop.makePromise()
        let proxyConnectHandler = NIOHTTP1ProxyConnectHandler(
            targetHost: "swift.org",
            targetPort: 443,
            headers: [:],
            deadline: .now() + .seconds(10),
            promise: promise
        )

        XCTAssertNoThrow(try embedded.pipeline.syncOperations.addHandler(proxyConnectHandler))

        let head = try XCTUnwrap(try embedded.readOutbound(as: HTTPClientRequestPart.self)).assertHead()
        XCTAssertEqual(head.method, .CONNECT)
        XCTAssertEqual(head.uri, "swift.org:443")
        XCTAssertNil(head.headers["proxy-authorization"].first)
        XCTAssertEqual(try embedded.readOutbound(as: HTTPClientRequestPart.self), .end(nil))

        let responseHead = HTTPResponseHead(version: .http1_1, status: .ok)
        XCTAssertNoThrow(try embedded.writeInbound(HTTPClientResponsePart.head(responseHead)))
        XCTAssertNoThrow(try embedded.writeInbound(HTTPClientResponsePart.end(nil)))

        XCTAssertNoThrow(try promise.futureResult.wait())
    }

    func testProxyConnectWithAuthorization() throws {
        let embedded = EmbeddedChannel()

        let socketAddress = try! SocketAddress.makeAddressResolvingHost("localhost", port: 0)
        XCTAssertNoThrow(try embedded.connect(to: socketAddress).wait())

        let promise: EventLoopPromise<Void> = embedded.eventLoop.makePromise()
        let proxyConnectHandler = NIOHTTP1ProxyConnectHandler(
            targetHost: "swift.org",
            targetPort: 443,
            headers: ["proxy-authorization": "Basic abc123"],
            deadline: .now() + .seconds(10),
            promise: promise
        )

        XCTAssertNoThrow(try embedded.pipeline.syncOperations.addHandler(proxyConnectHandler))

        let head = try XCTUnwrap(try embedded.readOutbound(as: HTTPClientRequestPart.self)).assertHead()
        XCTAssertEqual(head.method, .CONNECT)
        XCTAssertEqual(head.uri, "swift.org:443")
        XCTAssertEqual(head.headers["proxy-authorization"].first, "Basic abc123")
        XCTAssertEqual(try embedded.readOutbound(as: HTTPClientRequestPart.self), .end(nil))

        let responseHead = HTTPResponseHead(version: .http1_1, status: .ok)
        XCTAssertNoThrow(try embedded.writeInbound(HTTPClientResponsePart.head(responseHead)))
        XCTAssertNoThrow(try embedded.writeInbound(HTTPClientResponsePart.end(nil)))

        XCTAssertNoThrow(try promise.futureResult.wait())
    }

    func testProxyConnectWithoutAuthorizationFailure500() throws {
        let embedded = EmbeddedChannel()

        let socketAddress = try! SocketAddress.makeAddressResolvingHost("localhost", port: 0)
        XCTAssertNoThrow(try embedded.connect(to: socketAddress).wait())

        let promise: EventLoopPromise<Void> = embedded.eventLoop.makePromise()
        let proxyConnectHandler = NIOHTTP1ProxyConnectHandler(
            targetHost: "swift.org",
            targetPort: 443,
            headers: [:],
            deadline: .now() + .seconds(10),
            promise: promise
        )

        XCTAssertNoThrow(try embedded.pipeline.syncOperations.addHandler(proxyConnectHandler))

        let head = try XCTUnwrap(try embedded.readOutbound(as: HTTPClientRequestPart.self)).assertHead()
        XCTAssertEqual(head.method, .CONNECT)
        XCTAssertEqual(head.uri, "swift.org:443")
        XCTAssertNil(head.headers["proxy-authorization"].first)
        XCTAssertEqual(try embedded.readOutbound(as: HTTPClientRequestPart.self), .end(nil))

        let responseHead = HTTPResponseHead(version: .http1_1, status: .internalServerError)
        // answering with 500 should lead to a triggered error in pipeline
        XCTAssertThrowsError(try embedded.writeInbound(HTTPClientResponsePart.head(responseHead))) {
            XCTAssertEqual($0 as? NIOHTTP1ProxyConnectHandler.Error, .invalidProxyResponseHead(responseHead))
        }
        XCTAssertFalse(embedded.isActive, "Channel should be closed in response to the error")
        XCTAssertNoThrow(try embedded.writeInbound(HTTPClientResponsePart.end(nil)))

        XCTAssertThrowsError(try promise.futureResult.wait()) {
            XCTAssertEqual($0 as? NIOHTTP1ProxyConnectHandler.Error, .invalidProxyResponseHead(responseHead))
        }
    }

    func testProxyConnectWithoutAuthorizationButAuthorizationNeeded() throws {
        let embedded = EmbeddedChannel()

        let socketAddress = try! SocketAddress.makeAddressResolvingHost("localhost", port: 0)
        XCTAssertNoThrow(try embedded.connect(to: socketAddress).wait())

        let promise: EventLoopPromise<Void> = embedded.eventLoop.makePromise()
        let proxyConnectHandler = NIOHTTP1ProxyConnectHandler(
            targetHost: "swift.org",
            targetPort: 443,
            headers: [:],
            deadline: .now() + .seconds(10),
            promise: promise
        )

        XCTAssertNoThrow(try embedded.pipeline.syncOperations.addHandler(proxyConnectHandler))

        let head = try XCTUnwrap(try embedded.readOutbound(as: HTTPClientRequestPart.self)).assertHead()
        XCTAssertEqual(head.method, .CONNECT)
        XCTAssertEqual(head.uri, "swift.org:443")
        XCTAssertNil(head.headers["proxy-authorization"].first)
        XCTAssertEqual(try embedded.readOutbound(as: HTTPClientRequestPart.self), .end(nil))

        let responseHead = HTTPResponseHead(version: .http1_1, status: .proxyAuthenticationRequired)
        // answering with 500 should lead to a triggered error in pipeline
        XCTAssertThrowsError(try embedded.writeInbound(HTTPClientResponsePart.head(responseHead))) {
            XCTAssertEqual($0 as? NIOHTTP1ProxyConnectHandler.Error, .proxyAuthenticationRequired())
        }
        XCTAssertFalse(embedded.isActive, "Channel should be closed in response to the error")
        XCTAssertNoThrow(try embedded.writeInbound(HTTPClientResponsePart.end(nil)))

        XCTAssertThrowsError(try promise.futureResult.wait()) {
            XCTAssertEqual($0 as? NIOHTTP1ProxyConnectHandler.Error, .proxyAuthenticationRequired())
        }
    }

    func testProxyConnectReceivesBody() {
        let embedded = EmbeddedChannel()

        let socketAddress = try! SocketAddress.makeAddressResolvingHost("localhost", port: 0)
        XCTAssertNoThrow(try embedded.connect(to: socketAddress).wait())

        let promise: EventLoopPromise<Void> = embedded.eventLoop.makePromise()
        let proxyConnectHandler = NIOHTTP1ProxyConnectHandler(
            targetHost: "swift.org",
            targetPort: 443,
            headers: [:],
            deadline: .now() + .seconds(10),
            promise: promise
        )

        XCTAssertNoThrow(try embedded.pipeline.syncOperations.addHandler(proxyConnectHandler))

        var maybeHead: HTTPClientRequestPart?
        XCTAssertNoThrow(maybeHead = try embedded.readOutbound(as: HTTPClientRequestPart.self))
        guard case .some(.head(let head)) = maybeHead else {
            return XCTFail("Expected the proxy connect handler to first send a http head part")
        }

        XCTAssertEqual(head.method, .CONNECT)
        XCTAssertEqual(head.uri, "swift.org:443")
        XCTAssertEqual(try embedded.readOutbound(as: HTTPClientRequestPart.self), .end(nil))

        let responseHead = HTTPResponseHead(version: .http1_1, status: .ok)
        XCTAssertNoThrow(try embedded.writeInbound(HTTPClientResponsePart.head(responseHead)))
        // answering with a body should lead to a triggered error in pipeline
        XCTAssertThrowsError(try embedded.writeInbound(HTTPClientResponsePart.body(ByteBuffer(bytes: [0, 1, 2, 3])))) {
            XCTAssertEqual($0 as? NIOHTTP1ProxyConnectHandler.Error, .invalidProxyResponse())
        }
        XCTAssertEqual(embedded.isActive, false)
        XCTAssertNoThrow(try embedded.writeInbound(HTTPClientResponsePart.end(nil)))

        XCTAssertThrowsError(try promise.futureResult.wait()) {
            XCTAssertEqual($0 as? NIOHTTP1ProxyConnectHandler.Error, .invalidProxyResponse())
        }
    }

    func testProxyConnectWithoutAuthorizationBufferedWrites() throws {
        let embedded = EmbeddedChannel()
        defer { XCTAssertNoThrow(try embedded.finish(acceptAlreadyClosed: false)) }

        let socketAddress = try! SocketAddress.makeAddressResolvingHost("localhost", port: 0)
        XCTAssertNoThrow(try embedded.connect(to: socketAddress).wait())

        let proxyConnectPromise: EventLoopPromise<Void> = embedded.eventLoop.makePromise()
        let proxyConnectHandler = NIOHTTP1ProxyConnectHandler(
            targetHost: "swift.org",
            targetPort: 443,
            headers: [:],
            deadline: .now() + .seconds(10),
            promise: proxyConnectPromise
        )

        XCTAssertNoThrow(try embedded.pipeline.syncOperations.addHandler(proxyConnectHandler))

        // write a request to be buffered inside the ProxyConnectHandler
        // it will be unbuffered when the handler completes and removes itself
        let requestHead = HTTPRequestHead(
            version: HTTPVersion(major: 1, minor: 1),
            method: .GET,
            uri: "http://apple.com"
        )
        var promises: [EventLoopPromise<Void>] = []
        promises.append(embedded.eventLoop.makePromise())
        embedded.pipeline.write(HTTPClientRequestPart.head(requestHead), promise: promises.last)

        promises.append(embedded.eventLoop.makePromise())
        embedded.pipeline.write(
            HTTPClientRequestPart.body(.byteBuffer(ByteBuffer(string: "Test"))),
            promise: promises.last
        )

        promises.append(embedded.eventLoop.makePromise())
        embedded.pipeline.write(HTTPClientRequestPart.end(nil), promise: promises.last)
        embedded.pipeline.flush()

        // read the connect header back
        let connectHead = try XCTUnwrap(try embedded.readOutbound(as: HTTPClientRequestPart.self)).assertHead()

        XCTAssertEqual(connectHead.method, .CONNECT)
        XCTAssertEqual(connectHead.uri, "swift.org:443")
        XCTAssertNil(connectHead.headers["proxy-authorization"].first)

        let connectTrailers = try XCTUnwrap(try embedded.readOutbound(as: HTTPClientRequestPart.self)).assertEnd()
        XCTAssertNil(connectTrailers)

        // ensure that nothing has been unbuffered by mistake
        XCTAssertNil(try embedded.readOutbound(as: HTTPClientRequestPart.self))

        let responseHead = HTTPResponseHead(version: .http1_1, status: .ok)
        XCTAssertNoThrow(try embedded.writeInbound(HTTPClientResponsePart.head(responseHead)))
        XCTAssertNoThrow(try embedded.writeInbound(HTTPClientResponsePart.end(nil)))

        XCTAssertNoThrow(try proxyConnectPromise.futureResult.wait())

        // read the buffered write back
        let bufferedHead = try XCTUnwrap(try embedded.readOutbound(as: HTTPClientRequestPart.self)).assertHead()

        XCTAssertEqual(bufferedHead.method, .GET)
        XCTAssertEqual(bufferedHead.uri, "http://apple.com")
        XCTAssertNil(bufferedHead.headers["proxy-authorization"].first)

        let bufferedBody = try XCTUnwrap(try embedded.readOutbound(as: HTTPClientRequestPart.self)).assertBody()
        XCTAssertEqual(bufferedBody, ByteBuffer(string: "Test"))

        let bufferedTrailers = try XCTUnwrap(try embedded.readOutbound(as: HTTPClientRequestPart.self)).assertEnd()
        XCTAssertNil(bufferedTrailers)

        let resultFutures = promises.map { $0.futureResult }
        XCTAssertNoThrow(_ = try EventLoopFuture.whenAllComplete(resultFutures, on: embedded.eventLoop).wait())
    }

    func testProxyConnectFailsBufferedWritesAreFailed() throws {
        let embedded = EmbeddedChannel()

        let socketAddress = try! SocketAddress.makeAddressResolvingHost("localhost", port: 0)
        XCTAssertNoThrow(try embedded.connect(to: socketAddress).wait())

        let proxyConnectPromise: EventLoopPromise<Void> = embedded.eventLoop.makePromise()
        let proxyConnectHandler = NIOHTTP1ProxyConnectHandler(
            targetHost: "swift.org",
            targetPort: 443,
            headers: [:],
            deadline: .now() + .seconds(10),
            promise: proxyConnectPromise
        )

        XCTAssertNoThrow(try embedded.pipeline.syncOperations.addHandler(proxyConnectHandler))

        // write a request to be buffered inside the ProxyConnectHandler
        // it will be unbuffered when the handler completes and removes itself
        let requestHead = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "apple.com")
        var promises: [EventLoopPromise<Void>] = []
        promises.append(embedded.eventLoop.makePromise())
        embedded.pipeline.write(HTTPClientRequestPart.head(requestHead), promise: promises.last)

        promises.append(embedded.eventLoop.makePromise())
        embedded.pipeline.write(
            HTTPClientRequestPart.body(.byteBuffer(ByteBuffer(string: "Test"))),
            promise: promises.last
        )

        promises.append(embedded.eventLoop.makePromise())
        embedded.pipeline.write(HTTPClientRequestPart.end(nil), promise: promises.last)
        embedded.pipeline.flush()

        // read the connect header back
        let connectHead = try XCTUnwrap(try embedded.readOutbound(as: HTTPClientRequestPart.self)).assertHead()

        XCTAssertEqual(connectHead.method, .CONNECT)
        XCTAssertEqual(connectHead.uri, "swift.org:443")
        XCTAssertNil(connectHead.headers["proxy-authorization"].first)

        let connectTrailers = try XCTUnwrap(try embedded.readOutbound(as: HTTPClientRequestPart.self)).assertEnd()
        XCTAssertNil(connectTrailers)

        // ensure that nothing has been unbuffered by mistake
        XCTAssertNil(try embedded.readOutbound(as: HTTPClientRequestPart.self))

        let responseHead = HTTPResponseHead(version: .http1_1, status: .internalServerError)
        XCTAssertThrowsError(try embedded.writeInbound(HTTPClientResponsePart.head(responseHead))) {
            XCTAssertEqual($0 as? NIOHTTP1ProxyConnectHandler.Error, .invalidProxyResponseHead(responseHead))
        }
        XCTAssertFalse(embedded.isActive, "Channel should be closed in response to the error")
        XCTAssertNoThrow(try embedded.writeInbound(HTTPClientResponsePart.end(nil)))

        XCTAssertThrowsError(try proxyConnectPromise.futureResult.wait()) {
            XCTAssertEqual($0 as? NIOHTTP1ProxyConnectHandler.Error, .invalidProxyResponseHead(responseHead))
        }

        // buffered writes are dropped
        XCTAssertNil(try embedded.readOutbound(as: HTTPClientRequestPart.self))

        // all outstanding buffered write promises should be completed
        let resultFutures = promises.map { $0.futureResult }
        XCTAssertNoThrow(_ = try EventLoopFuture.whenAllComplete(resultFutures, on: embedded.eventLoop).wait())
    }
}

struct HTTPRequestPartMismatch: Error {}

extension HTTPClientRequestPart {
    @discardableResult
    func assertHead(file: StaticString = #file, line: UInt = #line) throws -> HTTPRequestHead {
        switch self {
        case .head(let head):
            return head
        default:
            XCTFail("Expected .head but got \(self)", file: file, line: line)
            throw HTTPRequestPartMismatch()
        }
    }

    @discardableResult
    func assertBody(file: StaticString = #file, line: UInt = #line) throws -> ByteBuffer {
        switch self {
        case .body(.byteBuffer(let body)):
            return body
        default:
            XCTFail("Expected .body but got \(self)", file: file, line: line)
            throw HTTPRequestPartMismatch()
        }
    }

    @discardableResult
    func assertEnd(file: StaticString = #file, line: UInt = #line) throws -> HTTPHeaders? {
        switch self {
        case .end(let trailers):
            return trailers
        default:
            XCTFail("Expected .end but got \(self)", file: file, line: line)
            throw HTTPRequestPartMismatch()
        }
    }
}
