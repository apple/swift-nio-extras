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

class TestHandler: ChannelInboundHandler {
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
        case .data(let data):
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
        if var buffer = try! self.channel.readOutbound(as: ByteBuffer.self) {
            XCTAssertEqual(buffer.readBytes(length: buffer.readableBytes), bytes, line: line)
        } else if bytes.count > 0 {
            XCTFail("Expected bytes but found none")
        }
    }
    
    func writeInbound(_ bytes: [UInt8], line: UInt = #line) {
        try! self.channel.writeInbound(ByteBuffer(bytes: bytes))
    }
    
    func assertInbound(_ bytes: [UInt8], line: UInt = #line) {
        var buffer = try! self.channel.readInbound(as: ByteBuffer.self)
        XCTAssertEqual(buffer!.readBytes(length: buffer!.readableBytes), bytes, line: line)
    }
    
    func testTypicalWorkflow() {
        let greetingPromise = self.channel.eventLoop.makePromise(of: Void.self)
        let requestPromise = self.channel.eventLoop.makePromise(of: Void.self)
        let dataPromise = self.channel.eventLoop.makePromise(of: Void.self)
        
        let expectedGreeting = ClientGreeting(methods: [.noneRequired])
        let expectedRequest = SOCKSRequest(command: .connect, addressType: .address(try! .init(ipAddress: "127.0.0.1", port: 80)))
        let expectedData = ByteBuffer(string: "1234")
        let testHandler = TestHandler(
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
        XCTAssertNoThrow(try self.channel.writeOutbound(ServerMessage.selectedAuthenticationMethod(.init(method: .noneRequired))))
        self.assertOutputBuffer([0x05, 0x00])
        
        // finish authentication - nothing should be written
        // as this is informing the state machine only
        XCTAssertNoThrow(try self.channel.writeOutbound(ServerMessage.authenticationComplete))
        self.assertOutputBuffer([])
        
        // write the request
        self.writeInbound([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
        XCTAssertNoThrow(try requestPromise.futureResult.wait())
    }
    
    func testTypicalWorkflowDripfeed() {
        let greetingPromise = self.channel.eventLoop.makePromise(of: Void.self)
        let requestPromise = self.channel.eventLoop.makePromise(of: Void.self)
        let dataPromise = self.channel.eventLoop.makePromise(of: Void.self)
        
        let expectedGreeting = ClientGreeting(methods: [.noneRequired])
        let expectedRequest = SOCKSRequest(command: .connect, addressType: .address(try! .init(ipAddress: "127.0.0.1", port: 80)))
        let expectedData = ByteBuffer(string: "1234")
        let testHandler = TestHandler(
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
        self.assertOutputBuffer(<#T##bytes: [UInt8]##[UInt8]#>)
    }
}
