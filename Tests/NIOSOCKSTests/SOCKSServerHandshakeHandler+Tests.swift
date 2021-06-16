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

import NIO
@testable import NIOSOCKS
import XCTest

class PromiseTestHandler: ChannelInboundHandler {
    typealias InboundIn = ClientMessage
    
    let expectedGreeting: ClientGreeting
    let greetingPromise: EventLoopPromise<Void>
    let expectedRequest: SOCKSRequest
    let requestPromise: EventLoopPromise<Void>
    let expectedData: ByteBuffer
    let dataPromise: EventLoopPromise<Void>
    
    public init(
        expectedGreeting: ClientGreeting,
        greetingPromise: EventLoopPromise<Void>,
        expectedRequest: SOCKSRequest,
        requestPromise: EventLoopPromise<Void>,
        expectedData: ByteBuffer,
        dataPromise: EventLoopPromise<Void>
    ) {
        self.expectedGreeting = expectedGreeting
        self.greetingPromise = greetingPromise
        self.expectedRequest = expectedRequest
        self.requestPromise = requestPromise
        self.expectedData = expectedData
        self.dataPromise = dataPromise
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = self.unwrapInboundIn(data)
        switch message {
        case .greeting(let greeting):
            XCTAssertEqual(greeting, expectedGreeting)
            greetingPromise.succeed(())
        case .request(let request):
            XCTAssertEqual(request, expectedRequest)
            requestPromise.succeed(())
        case .authenticationData(let data):
            XCTAssertEqual(data, expectedData)
            requestPromise.succeed(())
        }
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
                XCTFail("Expected bytes but found none")
            }
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func writeOutbound(_ message: ServerMessage, line: UInt = #line) {
        XCTAssertNoThrow(try self.channel.writeOutbound(message))
    }
    
    func writeInbound(_ bytes: [UInt8], line: UInt = #line) {
        XCTAssertNoThrow(try self.channel.writeInbound(ByteBuffer(bytes: bytes)))
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
                XCTFail("No message")
            }
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testTypicalWorkflow() {
        let greetingPromise = self.channel.eventLoop.makePromise(of: Void.self)
        let requestPromise = self.channel.eventLoop.makePromise(of: Void.self)
        let dataPromise = self.channel.eventLoop.makePromise(of: Void.self)
        
        let expectedGreeting = ClientGreeting(methods: [.noneRequired])
        let expectedRequest = SOCKSRequest(command: .connect, addressType: .address(try! .init(ipAddress: "127.0.0.1", port: 80)))
        let expectedData = ByteBuffer(string: "1234")
        let testHandler = PromiseTestHandler(
            expectedGreeting: expectedGreeting,
            greetingPromise: greetingPromise,
            expectedRequest: expectedRequest,
            requestPromise: requestPromise,
            expectedData: expectedData,
            dataPromise: dataPromise
        )
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(testHandler).wait())
        
        // wait for the greeting
        self.writeInbound([0x05, 0x01, 0x00])
        XCTAssertNoThrow(try greetingPromise.futureResult.wait())
        
        // write the auth selection
        self.writeOutbound(.selectedAuthenticationMethod(.init(method: .noneRequired)))
        self.assertOutputBuffer([0x05, 0x00])
        
        // finish authentication - nothing should be written
        // as this is informing the state machine only
        self.writeOutbound(.authenticationComplete)
        self.assertOutputBuffer([])
        
        // write the request
        self.writeInbound([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
        XCTAssertNoThrow(try requestPromise.futureResult.wait())
        self.writeOutbound(.response(.init(reply: .succeeded, boundAddress: .address(try! .init(ipAddress: "127.0.0.1", port: 80)))))
        self.assertOutputBuffer([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
        
        // now send some data
        self.writeOutbound(.authenticationData(ByteBuffer(bytes: [0x01, 0x02, 0x03, 0x04])))
        self.assertOutputBuffer([0x01, 0x02, 0x03, 0x04])
    }
    
    // tests dripfeeding to ensure we buffer data correctly
    func testTypicalWorkflowDripfeed() {
        let greetingPromise = self.channel.eventLoop.makePromise(of: Void.self)
        let requestPromise = self.channel.eventLoop.makePromise(of: Void.self)
        let dataPromise = self.channel.eventLoop.makePromise(of: Void.self)
        
        let expectedGreeting = ClientGreeting(methods: [.noneRequired])
        let expectedRequest = SOCKSRequest(command: .connect, addressType: .address(try! .init(ipAddress: "127.0.0.1", port: 80)))
        let expectedData = ByteBuffer(string: "1234")
        let testHandler = PromiseTestHandler(
            expectedGreeting: expectedGreeting,
            greetingPromise: greetingPromise,
            expectedRequest: expectedRequest,
            requestPromise: requestPromise,
            expectedData: expectedData,
            dataPromise: dataPromise
        )
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(testHandler).wait())
        
        // wait for the greeting
        self.writeInbound([0x05])
        self.assertOutputBuffer([])
        self.writeInbound([0x01])
        self.assertOutputBuffer([])
        self.writeInbound([0x00])
        self.assertOutputBuffer([])
        XCTAssertNoThrow(try greetingPromise.futureResult.wait())
        
        // write the auth selection
        XCTAssertNoThrow(try self.channel.writeOutbound(ServerMessage.selectedAuthenticationMethod(.init(method: .noneRequired))))
        self.assertOutputBuffer([0x05, 0x00])
        
        // finish authentication - nothing should be written
        // as this is informing the state machine only
        XCTAssertNoThrow(try self.channel.writeOutbound(ServerMessage.authenticationComplete))
        self.assertOutputBuffer([])
        
        // write the request
        self.writeInbound([0x05, 0x01])
        self.assertOutputBuffer([])
        self.writeInbound([0x00, 0x01])
        self.assertOutputBuffer([])
        self.writeInbound([127, 0, 0, 1, 0, 80])
        XCTAssertNoThrow(try requestPromise.futureResult.wait())
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
        XCTAssertThrowsError(try self.channel.writeAndFlush(ServerMessage.authenticationComplete).wait()) { e in
            XCTAssertTrue(e is SOCKSError.InvalidServerState)
        }
    }
    
    func testFlushOnHandlerRemoved() {
        self.writeInbound([0x05, 0x01])
        self.assertInbound([])
        XCTAssertNoThrow(try self.channel.pipeline.removeHandler(self.handler).wait())
        self.assertInbound([0x05, 0x01])
    }
    
    func testForceHandlerRemovalAfterAuth() {
        
        // go through auth
        self.writeInbound([0x05, 0x01, 0x00])
        self.writeOutbound(.selectedAuthenticationMethod(.init(method: .noneRequired)))
        self.assertOutputBuffer([0x05, 0x00])
        XCTAssertNoThrow(try self.handler.stateMachine.authenticationComplete())
        self.writeInbound([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
        self.writeOutbound(.response(.init(reply: .succeeded, boundAddress: .address(try! .init(ipAddress: "127.0.0.1", port: 80)))))
        self.assertOutputBuffer([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
        
        // auth complete, try to write data without
        // removing the handler, it should fail
        XCTAssertThrowsError(try self.channel.writeOutbound(ServerMessage.authenticationData(ByteBuffer(string: "hello, world!"))))
    }
    
    // tests going through the auth flow with the server sending
    // challenges and the client responding
    func testAuth() {
        self.writeInbound([0x05, 0x01, 0xAA])
        self.assertInbound(.greeting(.init(methods: [.init(value: 0xAA)])))

        self.writeOutbound(.selectedAuthenticationMethod(.init(method: .init(value: 0xAA))))
        self.assertOutputBuffer([0x05, 0xAA]) // some random made-up method
        
        self.writeInbound([0x01])
        self.assertInbound(.authenticationData(ByteBuffer(bytes: [0x01])))
        
        self.writeOutbound(.authenticationData(ByteBuffer(bytes: [0x02])))
        self.assertOutputBuffer([0x02])
        
        self.writeInbound([0x03])
        self.assertInbound(.authenticationData(ByteBuffer(bytes: [0x03])))
        
        XCTAssertNoThrow(try self.handler.stateMachine.authenticationComplete())
        self.writeInbound([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
        self.writeOutbound(.response(.init(reply: .succeeded, boundAddress: .address(try! .init(ipAddress: "127.0.0.1", port: 80)))))
        self.assertOutputBuffer([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
    }
}
