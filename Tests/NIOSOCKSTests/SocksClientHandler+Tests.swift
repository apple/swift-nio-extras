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
        self.handler = SOCKSClientHandler(targetAddress: .address(try! .init(ipAddress: "192.168.1.1", port: 80)))
        self.channel = EmbeddedChannel(handler: self.handler)
    }
    
    func connect() {
        try! self.channel.connect(to: .init(ipAddress: "127.0.0.1", port: 80)).wait()
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
        self.connect()
        
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

        // any outbound data should also go straight through
        XCTAssertNoThrow(try self.channel.writeOutbound(ByteBuffer(bytes: [1, 2, 3, 4, 5])))
        self.assertOutputBuffer([1, 2, 3, 4, 5])
    }
    
    // Tests that if we write alot of data at the start then
    // that data will be written after the client has completed
    // the socks handshake.
    func testThatBufferingWorks() {
        self.connect()
        
        let writePromise = self.channel.eventLoop.makePromise(of: Void.self)
        self.channel.writeAndFlush(ByteBuffer(bytes: [1, 2, 3, 4, 5]), promise: writePromise)
        self.assertOutputBuffer([0x05, 0x01, 0x00])
        self.writeInbound([0x05, 0x00])
        self.assertOutputBuffer([0x05, 0x01, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50])
        self.writeInbound([0x05, 0x00, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50])
        
        XCTAssertNoThrow(try writePromise.futureResult.wait())
        self.assertOutputBuffer([1, 2, 3, 4, 5])
    }
    
    func testBufferingWithMark() {
        self.connect()
        
        let writePromise1 = self.channel.eventLoop.makePromise(of: Void.self)
        let writePromise2 = self.channel.eventLoop.makePromise(of: Void.self)
        self.channel.write(ByteBuffer(bytes: [1, 2, 3]), promise: writePromise1)
        self.channel.flush()
        self.channel.write(ByteBuffer(bytes: [4, 5, 6]), promise: writePromise2)
        
        self.assertOutputBuffer([0x05, 0x01, 0x00])
        self.writeInbound([0x05, 0x00])
        self.assertOutputBuffer([0x05, 0x01, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50])
        self.writeInbound([0x05, 0x00, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50])
        
        XCTAssertNoThrow(try writePromise1.futureResult.wait())
        self.assertOutputBuffer([1, 2, 3])
        
        XCTAssertNoThrow(try self.channel.writeAndFlush(ByteBuffer(bytes: [7, 8, 9])).wait())
        XCTAssertNoThrow(try writePromise2.futureResult.wait())
        self.assertOutputBuffer([4, 5, 6])
        self.assertOutputBuffer([7, 8, 9])
    }
    
    func testTypicalWorkflowDripfeed() {
        self.connect()
        
        // the client should start the handshake instantly
        self.assertOutputBuffer([0x05, 0x01, 0x00])
        
        // server selects authentication method
        // once the dripfeed is complete we should get the client request
        self.writeInbound([0x05])
        self.assertOutputBuffer([])
        self.writeInbound([0x00])
        self.assertOutputBuffer([0x05, 0x01, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50])
        
        // drip feed server response
        self.writeInbound([0x05, 0x00, 0x00, 0x01])
        self.assertOutputBuffer([])
        self.writeInbound([192, 168])
        self.assertOutputBuffer([])
        self.writeInbound([1, 1])
        self.assertOutputBuffer([])
        self.writeInbound([0x00, 0x50])
        
        // any inbound data should now go straight through
        self.writeInbound([1, 2, 3, 4, 5])
        self.assertInbound([1, 2, 3, 4, 5])
    }
    
    func testInvalidAuthenticationMethod() {
        self.connect()
        
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
            XCTAssertTrue(e is SOCKSError.InvalidAuthenticationSelection)
        }
    }
    
    func testProxyConnectionFailed() {
        self.connect()
        
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
            XCTAssertEqual(e as? SOCKSError.ConnectionFailed, .init(reply: .serverFailure))
        }
    }
    
    func testDelayedConnection() {
        // we shouldn't start the handshake until the client
        // has connected
        self.assertOutputBuffer([])
        
        self.connect()
        
        // now the handshake should have started
        self.assertOutputBuffer([0x05, 0x01, 0x00])
    }
    
    func testDelayedHandlerAdded() {
        
        // reset the channel that was set up automatically
        XCTAssertNoThrow(try self.channel.close().wait())
        self.channel = EmbeddedChannel()
        self.handler = SOCKSClientHandler(targetAddress: .domain("127.0.0.1", port: 1234))
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "127.0.0.1", port: 80)).wait())
        XCTAssertTrue(self.channel.isActive)
        
        // there shouldn't be anything outbound
        self.assertOutputBuffer([])
        
        // add the handler, there should be outbound data immediately
        XCTAssertNoThrow(self.channel.pipeline.addHandler(handler))
        self.assertOutputBuffer([0x05, 0x01, 0x00])
    }

}
