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

class SocksClientHandlerTests: XCTestCase {
    
    var channel: EmbeddedChannel!
    var handler: SOCKSClientHandler!
    
    override func setUp() {
        XCTAssertNil(self.channel)
        self.handler = SOCKSClientHandler(
            supportedAuthenticationMethods: [.noneRequired],
            targetAddress: .ipv4([192, 168, 1, 1]),
            targetPort: 80,
            authenticationDelegate: DefaultAuthenticationDelegate()
        )
        self.channel = EmbeddedChannel(handler: self.handler)
        try! self.channel.connect(to: .init(ipAddress: "127.0.0.1", port: 80)).wait()
    }

    override func tearDown() {
        XCTAssertNotNil(self.channel)
        self.channel = nil
    }
    
    func assertOutputBuffer(_ bytes: [UInt8], line: UInt = #line) {
        var buffer = try! self.channel.readOutbound(as: ByteBuffer.self)
        XCTAssertEqual(buffer!.readBytes(length: buffer!.readableBytes), bytes, line: line)
    }
    
    func writeInbound(_ bytes: [UInt8], line: UInt = #line) {
        try! self.channel.writeInbound(ByteBuffer(bytes: bytes))
    }
    
    func assertInbound(_ bytes: [UInt8], line: UInt = #line) {
        var buffer = try! self.channel.readInbound(as: ByteBuffer.self)
        XCTAssertEqual(buffer!.readBytes(length: buffer!.readableBytes), bytes, line: line)
    }
    
    func testTypicalWorkflow() {
        
        // the client should start the handshake instantly
        self.assertOutputBuffer([0x05, 0x01, 0x00])
        
        // server selects an authentication method
        self.writeInbound([0x05, 0x00])
        
        // client sends the request
        self.assertOutputBuffer([0x05, 0x01, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50])
        
        // server replies yay or nay
        self.writeInbound([0x05, 0x00, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50])
        
        // any inbound data should now go straight through
        self.writeInbound([1, 2, 3, 4, 5])
        self.assertInbound([1, 2, 3, 4, 5])
        
    }
    
    func testInvalidAuthenticationMethod() {
        
        class ErrorHandler: ChannelInboundHandler {
            typealias InboundIn = ByteBuffer
            
            var promise: EventLoopPromise<Void>
            
            init(promise: EventLoopPromise<Void>) {
                self.promise = promise
            }
            
            func errorCaught(context: ChannelHandlerContext, error: Error) {
                promise.fail(error)
            }
        }
        
        self.assertOutputBuffer([0x05, 0x01, 0x00])
        
        // server requests an auth method we don't support
        let promise = self.channel.eventLoop.makePromise(of: Void.self)
        try! self.channel.pipeline.addHandler(ErrorHandler(promise: promise), position: .last).wait()
        self.writeInbound([0x05, 0x01])
        XCTAssertThrowsError(try promise.futureResult.wait()) { e in
            XCTAssertTrue(e is InvalidAuthenticationSelection)
        }
    }
    
    func testProxyConnectionFailed() {
        
        class ErrorHandler: ChannelInboundHandler {
            typealias InboundIn = ByteBuffer
            
            var promise: EventLoopPromise<Void>
            
            init(promise: EventLoopPromise<Void>) {
                self.promise = promise
            }
            
            func errorCaught(context: ChannelHandlerContext, error: Error) {
                promise.fail(error)
            }
        }
        
        // start handshake, send request
        self.assertOutputBuffer([0x05, 0x01, 0x00])
        self.writeInbound([0x05, 0x00])
        self.assertOutputBuffer([0x05, 0x01, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50])
        
        // server replies with an error
        let promise = self.channel.eventLoop.makePromise(of: Void.self)
        try! self.channel.pipeline.addHandler(ErrorHandler(promise: promise), position: .last).wait()
        self.writeInbound([0x05, 0x01, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50])
        XCTAssertThrowsError(try promise.futureResult.wait()) { e in
            XCTAssertEqual(e as? ConnectionFailed, .init(reply: .serverFailure))
        }
    }
}
