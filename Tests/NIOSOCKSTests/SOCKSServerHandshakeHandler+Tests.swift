//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2021 Apple Inc. and the SwiftNIO project authors
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
import XCTest

@testable import NIOSOCKS

class PromiseTestHandler: ChannelInboundHandler {
    typealias InboundIn = ClientMessage

    let expectedGreeting: ClientGreeting
    let expectedRequest: SOCKSRequest
    let expectedData: ByteBuffer

    var hadGreeting: Bool = false
    var hadRequest: Bool = false
    var hadData: Bool = false

    var hadSOCKSEstablishedProxyUserEvent: Bool = false

    public init(
        expectedGreeting: ClientGreeting,
        expectedRequest: SOCKSRequest,
        expectedData: ByteBuffer
    ) {
        self.expectedGreeting = expectedGreeting
        self.expectedRequest = expectedRequest
        self.expectedData = expectedData
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = self.unwrapInboundIn(data)
        switch message {
        case .greeting(let greeting):
            XCTAssertEqual(greeting, expectedGreeting)
            hadGreeting = true
        case .request(let request):
            XCTAssertEqual(request, expectedRequest)
            hadRequest = true
        case .authenticationData(let data):
            XCTAssertEqual(data, expectedData)
            hadData = true
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is SOCKSProxyEstablishedEvent:
            self.hadSOCKSEstablishedProxyUserEvent = true
        default:
            break
        }
        context.fireUserInboundEventTriggered(event)
    }
}

class SOCKSServerHandlerTests: XCTestCase {

    var channel: EmbeddedChannel!
    var handler: SOCKSServerHandshakeHandler!

    override func setUp() {
        XCTAssertNil(self.channel)
        self.handler = SOCKSServerHandshakeHandler()
        self.channel = EmbeddedChannel(handler: self.handler)
    }

    override func tearDown() {
        XCTAssertNotNil(self.channel)
        self.channel = nil
    }

    func assertOutputBuffer(_ bytes: [UInt8], line: UInt = #line) {
        do {
            if var buffer = try self.channel.readOutbound(as: ByteBuffer.self) {
                XCTAssertEqual(buffer.readBytes(length: buffer.readableBytes), bytes, line: line)
            } else if bytes.count > 0 {
                XCTFail("Expected bytes but found none", line: line)
            }
        } catch {
            XCTFail("\(error)", line: line)
        }
    }

    func writeOutbound(_ message: ServerMessage, line: UInt = #line) {
        XCTAssertNoThrow(try self.channel.writeOutbound(message), line: line)
    }

    func writeInbound(_ bytes: [UInt8], line: UInt = #line) {
        XCTAssertNoThrow(try self.channel.writeInbound(ByteBuffer(bytes: bytes)), line: line)
    }

    func assertInbound(_ bytes: [UInt8], line: UInt = #line) {
        do {
            if var buffer = try self.channel.readInbound(as: ByteBuffer.self) {
                XCTAssertEqual(buffer.readBytes(length: buffer.readableBytes), bytes, line: line)
            } else {
                XCTAssertTrue(bytes.count == 0)
            }
        } catch {
            XCTFail("\(error)")
        }
    }

    func assertInbound(_ message: ClientMessage, line: UInt = #line) {
        do {
            if let actual = try self.channel.readInbound(as: ClientMessage.self) {
                XCTAssertEqual(message, actual, line: line)
            } else {
                XCTFail("No message", line: line)
            }
        } catch {
            XCTFail("\(error)", line: line)
        }
    }

    func testTypicalWorkflow() {
        let expectedGreeting = ClientGreeting(methods: [.init(value: 0xAA)])
        let expectedRequest = SOCKSRequest(
            command: .connect,
            addressType: .address(try! .init(ipAddress: "127.0.0.1", port: 80))
        )
        let expectedData = ByteBuffer(bytes: [0x01, 0x02, 0x03, 0x04])
        let testHandler = PromiseTestHandler(
            expectedGreeting: expectedGreeting,
            expectedRequest: expectedRequest,
            expectedData: expectedData
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(testHandler))

        // wait for the greeting
        XCTAssertFalse(testHandler.hadGreeting)
        self.writeInbound([0x05, 0x01, 0xAA])
        XCTAssertTrue(testHandler.hadGreeting)

        // write the auth selection
        self.writeOutbound(.selectedAuthenticationMethod(.init(method: .init(value: 0xAA))))
        self.assertOutputBuffer([0x05, 0xAA])

        XCTAssertFalse(testHandler.hadData)
        self.writeInbound([0x01, 0x02, 0x03, 0x04])
        XCTAssertTrue(testHandler.hadData)

        // finish authentication - nothing should be written
        // as this is informing the state machine only
        self.writeOutbound(.authenticationData(ByteBuffer(bytes: [0xFF, 0xFF]), complete: true))
        self.assertOutputBuffer([0xFF, 0xFF])

        // write the request
        XCTAssertFalse(testHandler.hadRequest)
        self.writeInbound([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
        XCTAssertTrue(testHandler.hadRequest)
        XCTAssertFalse(testHandler.hadSOCKSEstablishedProxyUserEvent)
        self.writeOutbound(
            .response(.init(reply: .succeeded, boundAddress: .address(try! .init(ipAddress: "127.0.0.1", port: 80))))
        )
        XCTAssertTrue(testHandler.hadSOCKSEstablishedProxyUserEvent)
        self.assertOutputBuffer([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
    }

    // tests dripfeeding to ensure we buffer data correctly
    func testTypicalWorkflowDripfeed() {
        let expectedGreeting = ClientGreeting(methods: [.gssapi])
        let expectedRequest = SOCKSRequest(
            command: .connect,
            addressType: .address(try! .init(ipAddress: "127.0.0.1", port: 80))
        )
        let expectedData = ByteBuffer(string: "1234")
        let testHandler = PromiseTestHandler(
            expectedGreeting: expectedGreeting,
            expectedRequest: expectedRequest,
            expectedData: expectedData
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(testHandler))

        // wait for the greeting
        XCTAssertFalse(testHandler.hadGreeting)
        self.writeInbound([0x05])
        self.assertOutputBuffer([])
        self.writeInbound([0x01])
        self.assertOutputBuffer([])
        self.writeInbound([0x01])
        self.assertOutputBuffer([])
        XCTAssertTrue(testHandler.hadGreeting)

        // write the auth selection
        XCTAssertNoThrow(
            try self.channel.writeOutbound(ServerMessage.selectedAuthenticationMethod(.init(method: .gssapi)))
        )
        self.assertOutputBuffer([0x05, 0x01])

        // finish authentication with some bytes
        XCTAssertNoThrow(
            try self.channel.writeOutbound(
                ServerMessage.authenticationData(ByteBuffer(bytes: [0xFF, 0xFF]), complete: true)
            )
        )
        self.assertOutputBuffer([0xFF, 0xFF])

        // write the request
        XCTAssertFalse(testHandler.hadRequest)
        self.writeInbound([0x05, 0x01])
        self.assertOutputBuffer([])
        self.writeInbound([0x00, 0x01])
        self.assertOutputBuffer([])
        self.writeInbound([127, 0, 0, 1, 0, 80])
        XCTAssertTrue(testHandler.hadRequest)
    }

    // write nonsense bytes that should be caught inbound
    func testInboundErrorsAreHandled() {
        let buffer = ByteBuffer(bytes: [0xFF, 0xFF, 0xFF])
        XCTAssertThrowsError(try self.channel.writeInbound(buffer)) { e in
            XCTAssertTrue(e is SOCKSError.InvalidProtocolVersion)
        }
    }

    // write something that will be be invalid for the state machine's
    // current state, causing an error to be thrown
    func testOutboundErrorsAreHandled() {
        XCTAssertThrowsError(
            try self.channel.writeAndFlush(
                ServerMessage.authenticationData(ByteBuffer(bytes: [0xFF, 0xFF]), complete: true)
            ).wait()
        ) { e in
            XCTAssertTrue(e is SOCKSError.InvalidServerState)
        }
    }

    func testFlushOnHandlerRemoved() {
        self.writeInbound([0x05, 0x01])
        self.assertInbound([])
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.removeHandler(self.handler).wait())
        self.assertInbound([0x05, 0x01])
    }

    func testForceHandlerRemovalAfterAuth() {

        // go through auth
        self.writeInbound([0x05, 0x01, 0x01])
        self.writeOutbound(.selectedAuthenticationMethod(.init(method: .gssapi)))
        self.assertOutputBuffer([0x05, 0x01])
        self.writeOutbound(.authenticationData(ByteBuffer(), complete: true))
        self.assertOutputBuffer([])
        self.writeInbound([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
        self.writeOutbound(
            .response(.init(reply: .succeeded, boundAddress: .address(try! .init(ipAddress: "127.0.0.1", port: 80))))
        )
        self.assertOutputBuffer([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 80])

        // auth complete, try to write data without
        // removing the handler, it should fail
        XCTAssertThrowsError(
            try self.channel.writeOutbound(
                ServerMessage.authenticationData(ByteBuffer(string: "hello, world!"), complete: false)
            )
        )
    }

    func testAutoAuthenticationComplete() {

        // server selects none-required, this should mean we can continue without
        // having to manually inform the state machine
        self.writeInbound([0x05, 0x01, 0x00])
        self.writeOutbound(.selectedAuthenticationMethod(.init(method: .noneRequired)))
        self.assertOutputBuffer([0x05, 0x00])

        // if we try and write the request then the data would be read
        // as authentication data, and so the server wouldn't reply
        // with a response
        self.writeInbound([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
        self.writeOutbound(
            .response(.init(reply: .succeeded, boundAddress: .address(try! .init(ipAddress: "127.0.0.1", port: 80))))
        )
        self.assertOutputBuffer([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
    }

    func testAutoAuthenticationCompleteWithManualCompletion() {

        // server selects none-required, this should mean we can continue without
        // having to manually inform the state machine. However, informing the state
        // machine manually shouldn't break anything.
        self.writeInbound([0x05, 0x01, 0x00])
        self.writeOutbound(.selectedAuthenticationMethod(.init(method: .noneRequired)))
        self.assertOutputBuffer([0x05, 0x00])

        // complete authentication, but nothing should be written
        // to the network
        self.writeOutbound(.authenticationData(ByteBuffer(), complete: true))
        self.assertOutputBuffer([])

        // if we try and write the request then the data would be read
        // as authentication data, and so the server wouldn't reply
        // with a response
        self.writeInbound([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
        self.writeOutbound(
            .response(.init(reply: .succeeded, boundAddress: .address(try! .init(ipAddress: "127.0.0.1", port: 80))))
        )
        self.assertOutputBuffer([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
    }

    func testEagerClientRequestBeforeAuthenticationComplete() {

        // server selects none-required, this should mean we can continue without
        // having to manually inform the state machine. However, informing the state
        // machine manually shouldn't break anything.
        self.writeInbound([0x05, 0x01, 0x01])
        self.assertInbound(.greeting(.init(methods: [.gssapi])))
        self.writeOutbound(.selectedAuthenticationMethod(.init(method: .gssapi)))
        self.assertOutputBuffer([0x05, 0x01])

        // at this point authentication isn't complete
        // so if the client sends a request then the
        // server will read those as authentication bytes
        self.writeInbound([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
        self.assertInbound(.authenticationData(ByteBuffer(bytes: [0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80])))
    }

    func testManualAuthenticationFailureExtraBytes() {
        // server selects none-required, this should mean we can continue without
        // having to manually inform the state machine. However, informing the state
        // machine manually shouldn't break anything.
        self.writeInbound([0x05, 0x01, 0x00])
        self.writeOutbound(.selectedAuthenticationMethod(.init(method: .noneRequired)))
        self.assertOutputBuffer([0x05, 0x00])

        // invalid authentication completion
        // we've selected `noneRequired`, so no
        // bytes should be written
        XCTAssertThrowsError(
            try self.channel.writeOutbound(ServerMessage.authenticationData(ByteBuffer(bytes: [0x00]), complete: true))
        )
    }

    func testManualAuthenticationFailureInvalidCompletion() {
        // server selects none-required, this should mean we can continue without
        // having to manually inform the state machine. However, informing the state
        // machine manually shouldn't break anything.
        self.writeInbound([0x05, 0x01, 0x00])
        self.writeOutbound(.selectedAuthenticationMethod(.init(method: .noneRequired)))
        self.assertOutputBuffer([0x05, 0x00])

        // invalid authentication completion
        // authentication should have already completed
        // as we selected `noneRequired`, so sending
        // `complete = false` should be an error
        XCTAssertThrowsError(
            try self.channel.writeOutbound(ServerMessage.authenticationData(ByteBuffer(bytes: []), complete: false))
        )
    }
}
