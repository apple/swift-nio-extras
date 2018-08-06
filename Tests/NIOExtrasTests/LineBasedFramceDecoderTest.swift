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
import NIO
import NIOExtras

class LineBasedFrameDecoderTest: XCTestCase {
    
    private var channel: EmbeddedChannel!
    private var handler: LineBasedFrameDecoder!
    
    override func setUp() {
        self.channel = EmbeddedChannel()
        self.handler = LineBasedFrameDecoder()
        try? self.channel.pipeline.add(handler: self.handler).wait()
    }
    
    func testDecodeOneCharacterAtATime() throws {
        let message = "abcdefghij\r"
        // we write one character at a time
        try message.forEach {
            var buffer = self.channel.allocator.buffer(capacity: 1)
            buffer.write(string: "\($0)")
            XCTAssertFalse(try self.channel.writeInbound(buffer))
        }
        // let's add `\n`
        var buffer = self.channel.allocator.buffer(capacity: 1)
        buffer.write(string: "\n")
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = self.channel.readInbound()
        XCTAssertEqual("abcdefghij", outputBuffer?.readString(length: 10))
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testRemoveHandlerWhenBufferIsNotEmpty() throws {
        var buffer = self.channel.allocator.buffer(capacity: 8)
        buffer.write(string: "foo\r\nbar")
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        var outputBuffer: ByteBuffer? = self.channel.readInbound()
        XCTAssertEqual(3, outputBuffer?.readableBytes)
        XCTAssertEqual("foo", outputBuffer?.readString(length: 3))
        
        _ = try self.channel.pipeline.remove(handler: handler).wait()
        XCTAssertThrowsError(try self.channel.throwIfErrorCaught()) { error in
            guard let error = error as? NIOExtrasErrors.LeftOverBytesError else {
                XCTFail()
                return
            }
            
            var expectedBuffer = self.channel.allocator.buffer(capacity: 7)
            expectedBuffer.write(string: "bar")
            XCTAssertEqual(error.leftOverBytes, expectedBuffer)
        }
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testRemoveHandlerWhenBufferIsEmpty() throws {
        var buffer = self.channel.allocator.buffer(capacity: 4)
        buffer.write(string: "foo\n")
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = self.channel.readInbound()
        XCTAssertEqual("foo", outputBuffer?.readString(length: 3))
        
        _ = try self.channel.pipeline.remove(handler: handler).wait()
        XCTAssertNoThrow(try self.channel.throwIfErrorCaught())
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEmptyLine() throws {
        var buffer = self.channel.allocator.buffer(capacity: 1)
        buffer.write(string: "\n")
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = self.channel.readInbound()
        XCTAssertEqual("", outputBuffer?.readString(length: 0))
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEmptyBuffer() throws {
        var buffer = self.channel.allocator.buffer(capacity: 1)
        buffer.write(string: "")
        XCTAssertFalse(try self.channel.writeInbound(buffer))
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testReaderIndexNotZero() throws {
        var buffer = self.channel.allocator.buffer(capacity: 8)
        // read "abc" so the reader index is not 0
        buffer.write(string: "abcfoo\r\nbar")
        XCTAssertEqual("abc", buffer.readString(length: 3))
        XCTAssertEqual(3, buffer.readerIndex)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        var outputBuffer: ByteBuffer? = self.channel.readInbound()
        XCTAssertEqual(3, outputBuffer?.readableBytes)
        XCTAssertEqual("foo", outputBuffer?.readString(length: 3))
        // discard the read bytes - this will reset the reader index to 0
        var buf = self.handler.cumulationBuffer
        buf?.discardReadBytes()
        self.handler.cumulationBuffer = buf
        XCTAssertEqual(0, self.handler.cumulationBuffer?.readerIndex ?? -1)
        
        buffer.write(string: "\r\n")
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        outputBuffer = self.channel.readInbound()
        XCTAssertEqual("bar", outputBuffer?.readString(length: 3))
    }
    
    func testChannelInactiveWithLeftOverBytes() throws {
        // add some data to the buffer
        var buffer = self.channel.allocator.buffer(capacity: 2)
        // read "abc" so the reader index is not 0
        buffer.write(string: "hi")
        XCTAssertFalse(try self.channel.writeInbound(buffer))
        
        try self.channel.close().wait()
        XCTAssertThrowsError(try self.channel.throwIfErrorCaught()) { error in
            guard let error = error as? NIOExtrasErrors.LeftOverBytesError else {
                XCTFail()
                return
            }
            var expectedBuffer = self.channel.allocator.buffer(capacity: 7)
            expectedBuffer.write(string: "hi")
            XCTAssertEqual(error.leftOverBytes, expectedBuffer)
            // make sure we have cleared the buffer
            XCTAssertEqual(handler.cumulationBuffer?.readableBytes, 0)
        }
    }
}
