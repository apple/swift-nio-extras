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
@testable import NIOSOCKS
import XCTest

class SocksClientHandlerTests: XCTestCase {
    func connect(channel: EmbeddedChannel) {
        try! channel.connect(to: .init(ipAddress: "127.0.0.1", port: 80)).wait()
    }
    
    func assertOutputBuffer(_ bytes: [UInt8], channel: EmbeddedChannel, line: UInt = #line) {
        if var buffer = try! channel.readOutbound(as: ByteBuffer.self) {
            XCTAssertEqual(buffer.readBytes(length: buffer.readableBytes), bytes, line: line)
        } else if bytes.count > 0 {
            XCTFail("Expected bytes but found none")
        }
    }
    
    func writeInbound(_ bytes: [UInt8], channel: EmbeddedChannel, line: UInt = #line) {
        try! channel.writeInbound(ByteBuffer(bytes: bytes))
    }
    
    func assertInbound(_ bytes: [UInt8], channel: EmbeddedChannel, line: UInt = #line) {
        var buffer = try! channel.readInbound(as: ByteBuffer.self)
        XCTAssertEqual(buffer!.readBytes(length: buffer!.readableBytes), bytes, line: line)
    }
    
    func testTypicalWorkflow() {
        let handler = SOCKSClientHandler(targetAddress: .address(try! .init(ipAddress: "192.168.1.1", port: 80)))
        let channel = EmbeddedChannel(handler: handler)
        let clientHandler = MockSOCKSClientHandler()
        XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(clientHandler))
        
        self.connect(channel: channel)
        
        // the client should start the handshake instantly
        self.assertOutputBuffer([0x05, 0x01, 0x00], channel: channel)
        
        // server selects an authentication method
        self.writeInbound([0x05, 0x00], channel: channel)
        
        // client sends the request
        self.assertOutputBuffer([0x05, 0x01, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50], channel: channel)
        
        // server replies yay
        XCTAssertFalse(clientHandler.hadSOCKSEstablishedProxyUserEvent)
        self.writeInbound([0x05, 0x00, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50], channel: channel)
        XCTAssertTrue(clientHandler.hadSOCKSEstablishedProxyUserEvent)
        
        // any inbound data should now go straight through
        self.writeInbound([1, 2, 3, 4, 5], channel: channel)
        self.assertInbound([1, 2, 3, 4, 5], channel: channel)

        // any outbound data should also go straight through
        XCTAssertNoThrow(try channel.writeOutbound(ByteBuffer(bytes: [1, 2, 3, 4, 5])))
        self.assertOutputBuffer([1, 2, 3, 4, 5], channel: channel)
    }
    
    // Tests that if we write alot of data at the start then
    // that data will be written after the client has completed
    // the socks handshake.
    func testThatBufferingWorks() {
        let handler = SOCKSClientHandler(targetAddress: .address(try! .init(ipAddress: "192.168.1.1", port: 80)))
        let channel = EmbeddedChannel(handler: handler)
        self.connect(channel: channel)
        
        let writePromise = channel.eventLoop.makePromise(of: Void.self)
        channel.writeAndFlush(ByteBuffer(bytes: [1, 2, 3, 4, 5]), promise: writePromise)
        self.assertOutputBuffer([0x05, 0x01, 0x00], channel: channel)
        self.writeInbound([0x05, 0x00], channel: channel)
        self.assertOutputBuffer([0x05, 0x01, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50], channel: channel)
        self.writeInbound([0x05, 0x00, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50], channel: channel)
        
        XCTAssertNoThrow(try writePromise.futureResult.wait())
        self.assertOutputBuffer([1, 2, 3, 4, 5], channel: channel)
    }
    
    func testBufferingWithMark() {
        let handler = SOCKSClientHandler(targetAddress: .address(try! .init(ipAddress: "192.168.1.1", port: 80)))
        let channel = EmbeddedChannel(handler: handler)
        self.connect(channel: channel)
        
        let writePromise1 = channel.eventLoop.makePromise(of: Void.self)
        let writePromise2 = channel.eventLoop.makePromise(of: Void.self)
        channel.write(ByteBuffer(bytes: [1, 2, 3]), promise: writePromise1)
        channel.flush()
        channel.write(ByteBuffer(bytes: [4, 5, 6]), promise: writePromise2)
        
        self.assertOutputBuffer([0x05, 0x01, 0x00], channel: channel)
        self.writeInbound([0x05, 0x00], channel: channel)
        self.assertOutputBuffer([0x05, 0x01, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50], channel: channel)
        self.writeInbound([0x05, 0x00, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50], channel: channel)
        
        XCTAssertNoThrow(try writePromise1.futureResult.wait())
        self.assertOutputBuffer([1, 2, 3], channel: channel)
        
        XCTAssertNoThrow(try channel.writeAndFlush(ByteBuffer(bytes: [7, 8, 9])).wait())
        XCTAssertNoThrow(try writePromise2.futureResult.wait())
        self.assertOutputBuffer([4, 5, 6], channel: channel)
        self.assertOutputBuffer([7, 8, 9], channel: channel)
    }
    
    func testTypicalWorkflowDripfeed() {
        let handler = SOCKSClientHandler(targetAddress: .address(try! .init(ipAddress: "192.168.1.1", port: 80)))
        let channel = EmbeddedChannel(handler: handler)
        self.connect(channel: channel)
        
        // the client should start the handshake instantly
        self.assertOutputBuffer([0x05, 0x01, 0x00], channel: channel)
        
        // server selects authentication method
        // once the dripfeed is complete we should get the client request
        self.writeInbound([0x05], channel: channel)
        self.assertOutputBuffer([], channel: channel)
        self.writeInbound([0x00], channel: channel)
        self.assertOutputBuffer([0x05, 0x01, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50], channel: channel)
        
        // drip feed server response
        self.writeInbound([0x05, 0x00, 0x00, 0x01], channel: channel)
        self.assertOutputBuffer([], channel: channel)
        self.writeInbound([192, 168], channel: channel)
        self.assertOutputBuffer([], channel: channel)
        self.writeInbound([1, 1], channel: channel)
        self.assertOutputBuffer([], channel: channel)
        self.writeInbound([0x00, 0x50], channel: channel)
        
        // any inbound data should now go straight through
        self.writeInbound([1, 2, 3, 4, 5], channel: channel)
        self.assertInbound([1, 2, 3, 4, 5], channel: channel)
    }
    
    func testInvalidAuthenticationMethod() {
        let handler = SOCKSClientHandler(targetAddress: .address(try! .init(ipAddress: "192.168.1.1", port: 80)))
        let channel = EmbeddedChannel(handler: handler)
        self.connect(channel: channel)
        
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
        
        self.assertOutputBuffer([0x05, 0x01, 0x00], channel: channel)
        
        // server requests an auth method we don't support
        let promise = channel.eventLoop.makePromise(of: Void.self)
        try! channel.pipeline.addHandler(ErrorHandler(promise: promise), position: .last).wait()
        self.writeInbound([0x05, 0x01], channel: channel)
        XCTAssertThrowsError(try promise.futureResult.wait()) { e in
            XCTAssertTrue(e is SOCKSError.InvalidAuthenticationSelection)
        }
    }
    
    func testProxyConnectionFailed() {
        let handler = SOCKSClientHandler(targetAddress: .address(try! .init(ipAddress: "192.168.1.1", port: 80)))
        let channel = EmbeddedChannel(handler: handler)
        self.connect(channel: channel)
        
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
        self.assertOutputBuffer([0x05, 0x01, 0x00], channel: channel)
        self.writeInbound([0x05, 0x00], channel: channel)
        self.assertOutputBuffer([0x05, 0x01, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50], channel: channel)
        
        // server replies with an error
        let promise = channel.eventLoop.makePromise(of: Void.self)
        try! channel.pipeline.addHandler(ErrorHandler(promise: promise), position: .last).wait()
        self.writeInbound([0x05, 0x01, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50], channel: channel)
        XCTAssertThrowsError(try promise.futureResult.wait()) { e in
            XCTAssertEqual(e as? SOCKSError.ConnectionFailed, .init(reply: .serverFailure))
        }
    }
    
    func testDelayedConnection() {
        let handler = SOCKSClientHandler(targetAddress: .address(try! .init(ipAddress: "192.168.1.1", port: 80)))
        let channel = EmbeddedChannel(handler: handler)
        
        // we shouldn't start the handshake until the client
        // has connected
        self.assertOutputBuffer([], channel: channel)
        
        self.connect(channel: channel)
        
        // now the handshake should have started
        self.assertOutputBuffer([0x05, 0x01, 0x00], channel: channel)
    }
    
    func testDelayedHandlerAdded() {
        let channel = EmbeddedChannel()
        let handler = SOCKSClientHandler(targetAddress: .domain("127.0.0.1", port: 1234))
        XCTAssertNoThrow(try channel.connect(to: .init(ipAddress: "127.0.0.1", port: 80)).wait())
        XCTAssertTrue(channel.isActive)
        
        // there shouldn't be anything outbound
        self.assertOutputBuffer([], channel: channel)
        
        // add the handler, there should be outbound data immediately
        XCTAssertNoThrow(channel.pipeline.addHandler(handler))
        self.assertOutputBuffer([0x05, 0x01, 0x00], channel: channel)
    }
    
    func testHandlerRemovalAfterEstablishEvent() {
        class SOCKSEventHandler: ChannelInboundHandler {
            typealias InboundIn = NIOAny
            
            var establishedPromise: EventLoopPromise<Void>
            
            init(establishedPromise: EventLoopPromise<Void>) {
                self.establishedPromise = establishedPromise
            }
            
            func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
                switch event {
                case is SOCKSProxyEstablishedEvent:
                    self.establishedPromise.succeed(())
                default:
                    break
                }
                context.fireUserInboundEventTriggered(event)
            }
        }

        let channel = EmbeddedChannel(handler: SOCKSClientHandler(targetAddress: .address(try! .init(ipAddress: "192.168.1.1", port: 80))))
        let establishPromise = channel.eventLoop.makePromise(of: Void.self)
        let removalPromise = channel.eventLoop.makePromise(of: Void.self)
        establishPromise.futureResult.whenSuccess { _ in
            channel.pipeline.handler(type: SOCKSClientHandler.self).whenSuccess {
                channel.pipeline.removeHandler($0).cascade(to: removalPromise)
            }
        }
        
        XCTAssertNoThrow(try channel.pipeline.addHandler(SOCKSEventHandler(establishedPromise: establishPromise)).wait())
        
        self.connect(channel: channel)
        
        // these writes should be buffered to be send out once the connection is established.
        channel.write(ByteBuffer(bytes: [1, 2, 3]), promise: nil)
        channel.flush()
        channel.write(ByteBuffer(bytes: [4, 5, 6]), promise: nil)
        
        self.assertOutputBuffer([0x05, 0x01, 0x00], channel: channel)
        self.writeInbound([0x05, 0x00], channel: channel)
        self.assertOutputBuffer([0x05, 0x01, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50], channel: channel)
        self.writeInbound([0x05, 0x00, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50], channel: channel)
        
        self.assertOutputBuffer([1, 2, 3], channel: channel)
        
        XCTAssertNoThrow(try channel.writeAndFlush(ByteBuffer(bytes: [7, 8, 9])).wait())
        
        self.assertOutputBuffer([4, 5, 6], channel: channel)
        self.assertOutputBuffer([7, 8, 9], channel: channel)
        
        XCTAssertNoThrow(try removalPromise.futureResult.wait())
        XCTAssertThrowsError(try channel.pipeline.syncOperations.handler(type: SOCKSClientHandler.self)) {
            XCTAssertEqual($0 as? ChannelPipelineError, .notFound)
        }
    }
    
    func testHandlerRemovalBeforeConnectionIsEstablished() {
        let handler = SOCKSClientHandler(targetAddress: .address(try! .init(ipAddress: "192.168.1.1", port: 80)))
        let channel = EmbeddedChannel(handler: handler)
        
        self.connect(channel: channel)
        
        // these writes should be buffered to be send out once the connection is established.
        channel.write(ByteBuffer(bytes: [1, 2, 3]), promise: nil)
        channel.flush()
        channel.write(ByteBuffer(bytes: [4, 5, 6]), promise: nil)
        
        self.assertOutputBuffer([0x05, 0x01, 0x00], channel: channel)
        self.writeInbound([0x05, 0x00], channel: channel)
        self.assertOutputBuffer([0x05, 0x01, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50], channel: channel)
        
        // we try to remove the handler before the connection is established.
        let removalPromise = channel.eventLoop.makePromise(of: Void.self)
        channel.pipeline.removeHandler(handler, promise: removalPromise)
        
        // establishes the connection
        self.writeInbound([0x05, 0x00, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50], channel: channel)
        
        // write six more bytes - those should be passed through right away
        self.writeInbound([1, 2, 3, 4, 5, 6], channel: channel)
        self.assertInbound([1, 2, 3, 4, 5, 6], channel: channel)
        
        self.assertOutputBuffer([1, 2, 3], channel: channel)
        
        XCTAssertNoThrow(try channel.writeAndFlush(ByteBuffer(bytes: [7, 8, 9])).wait())
        
        self.assertOutputBuffer([4, 5, 6], channel: channel)
        self.assertOutputBuffer([7, 8, 9], channel: channel)
        
        XCTAssertNoThrow(try removalPromise.futureResult.wait())
        XCTAssertThrowsError(try channel.pipeline.syncOperations.handler(type: SOCKSClientHandler.self)) {
            XCTAssertEqual($0 as? ChannelPipelineError, .notFound)
        }
    }
}

class MockSOCKSClientHandler: ChannelInboundHandler {
    typealias InboundIn = NIOAny
    
    var hadSOCKSEstablishedProxyUserEvent: Bool = false
    
    init() {}
    
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
