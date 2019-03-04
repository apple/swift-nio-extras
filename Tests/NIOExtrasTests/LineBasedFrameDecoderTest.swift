//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import XCTest
@testable import NIO // to inspect the cumulationBuffer
import NIOExtras

class LineBasedFrameDecoderTest: XCTestCase {
    private var channel: EmbeddedChannel!
    private var decoder: LineBasedFrameDecoder!
    private var handler: ByteToMessageHandler<LineBasedFrameDecoder>!
    
    override func setUp() {
        self.channel = EmbeddedChannel()
        self.decoder = LineBasedFrameDecoder()
        self.handler = ByteToMessageHandler(self.decoder)
        try? self.channel.pipeline.addHandler(self.handler).wait()
    }

    override func tearDown() {
        self.decoder = nil
        self.handler = nil
        _ = try? self.channel.finish()
    }
    
    func testDecodeOneCharacterAtATime() throws {
        let message = "abcdefghij\r"
        // we write one character at a time
        try message.forEach {
            var buffer = self.channel.allocator.buffer(capacity: 1)
            buffer.writeString("\($0)")
            XCTAssertFalse(try self.channel.writeInbound(buffer))
        }
        // let's add `\n`
        var buffer = self.channel.allocator.buffer(capacity: 1)
        buffer.writeString("\n")
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        
        XCTAssertNoThrow(XCTAssertEqual("abcdefghij",
                                        (try self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
            String(decoding: $0[0..<10], as: Unicode.UTF8.self)
        }))
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testRemoveHandlerWhenBufferIsNotEmpty() throws {
        var buffer = self.channel.allocator.buffer(capacity: 8)
        buffer.writeString("foo\r\nbar")
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        var outputBuffer: ByteBuffer? = try self.channel.readInbound()
        XCTAssertEqual(3, outputBuffer?.readableBytes)
        XCTAssertEqual("foo", outputBuffer?.readString(length: 3))
        
        let removeFuture = self.channel.pipeline.removeHandler(self.handler)
        (self.channel.eventLoop as! EmbeddedEventLoop).run()
        XCTAssertNoThrow(try removeFuture.wait())
        XCTAssertThrowsError(try self.channel.throwIfErrorCaught()) { error in
            guard let error = error as? NIOExtrasErrors.LeftOverBytesError else {
                XCTFail()
                return
            }
            
            var expectedBuffer = self.channel.allocator.buffer(capacity: 7)
            expectedBuffer.writeString("bar")
            XCTAssertEqual(error.leftOverBytes, expectedBuffer)
        }
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testRemoveHandlerWhenBufferIsEmpty() throws {
        var buffer = self.channel.allocator.buffer(capacity: 4)
        buffer.writeString("foo\n")
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = try self.channel.readInbound()
        XCTAssertEqual("foo", outputBuffer?.readString(length: 3))
        
        let removeFuture = self.channel.pipeline.removeHandler(self.handler)
        (self.channel.eventLoop as! EmbeddedEventLoop).run()
        XCTAssertNoThrow(try removeFuture.wait())
        XCTAssertNoThrow(try self.channel.throwIfErrorCaught())
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEmptyLine() throws {
        var buffer = self.channel.allocator.buffer(capacity: 1)
        buffer.writeString("\n")
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = try self.channel.readInbound()
        XCTAssertEqual("", outputBuffer?.readString(length: 0))
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEmptyBuffer() throws {
        var buffer = self.channel.allocator.buffer(capacity: 1)
        buffer.writeString("")
        XCTAssertFalse(try self.channel.writeInbound(buffer))
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testChannelInactiveWithLeftOverBytes() throws {
        // add some data to the buffer
        var buffer = self.channel.allocator.buffer(capacity: 2)
        // read "abc" so the reader index is not 0
        buffer.writeString("hi")
        XCTAssertFalse(try self.channel.writeInbound(buffer))
        
        try self.channel.close().wait()
        XCTAssertThrowsError(try self.channel.throwIfErrorCaught()) { error in
            guard let error = error as? NIOExtrasErrors.LeftOverBytesError else {
                XCTFail()
                return
            }
            var expectedBuffer = self.channel.allocator.buffer(capacity: 7)
            expectedBuffer.writeString("hi")
            XCTAssertEqual(error.leftOverBytes, expectedBuffer)
        }
    }
}
