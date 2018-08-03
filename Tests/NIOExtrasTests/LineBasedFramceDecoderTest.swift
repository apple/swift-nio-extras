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
    
    func testDecodeOneCharacterAtATime() throws {
        let channel = EmbeddedChannel()
        try channel.pipeline.add(handler: LineBasedFrameDecoder()).wait()
        
        let message = "abcdefghij\r"
        // we write one character at a time
        try message.forEach {
            var buffer = channel.allocator.buffer(capacity: 1)
            buffer.write(string: "\($0)")
            XCTAssertFalse(try channel.writeInbound(buffer))
        }
        // let's add `\n`
        var buffer = channel.allocator.buffer(capacity: 1)
        buffer.write(string: "\n")
        XCTAssertTrue(try channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = channel.readInbound()
        XCTAssertEqual("abcdefghij", outputBuffer?.readString(length: 10))
        XCTAssertFalse(try channel.finish())
    }
    
    func testRemoveHandlerWhenBufferIsNotEmpty() throws {
        let channel = EmbeddedChannel()
        let handler = LineBasedFrameDecoder()
        try channel.pipeline.add(handler: handler).wait()
        
        var buffer = channel.allocator.buffer(capacity: 8)
        buffer.write(string: "foo\r\nbar")
        XCTAssertTrue(try channel.writeInbound(buffer))
        var outputBuffer: ByteBuffer? = channel.readInbound()
        XCTAssertEqual(3, outputBuffer?.readableBytes)
        XCTAssertEqual("foo", outputBuffer?.readString(length: 3))
        
        _ = try channel.pipeline.remove(handler: handler).wait()
        XCTAssertThrowsError(try channel.throwIfErrorCaught()) { error in
            guard let error = error as? NIOExtrasErrors.LeftOverBytesError else {
                XCTFail()
                return
            }
            
            var expectedBuffer = channel.allocator.buffer(capacity: 7)
            expectedBuffer.write(string: "bar")
            XCTAssertEqual(error.leftOverBytes, expectedBuffer)
        }
        XCTAssertFalse(try channel.finish())
    }
    
    func testRemoveHandlerWhenBufferIsEmpty() throws {
        let channel = EmbeddedChannel()
        
        let handler = LineBasedFrameDecoder()
        try channel.pipeline.add(handler: handler).wait()
        
        var buffer = channel.allocator.buffer(capacity: 4)
        buffer.write(string: "foo\n")
        XCTAssertTrue(try channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = channel.readInbound()
        XCTAssertEqual("foo", outputBuffer?.readString(length: 3))
        
        _ = try channel.pipeline.remove(handler: handler).wait()
        XCTAssertNoThrow(try channel.throwIfErrorCaught())
        XCTAssertFalse(try channel.finish())
    }
    
    func testEmptyLine() throws {
        let channel = EmbeddedChannel()
        try channel.pipeline.add(handler: LineBasedFrameDecoder()).wait()
        var buffer = channel.allocator.buffer(capacity: 1)
        buffer.write(string: "\n")
        XCTAssertTrue(try channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = channel.readInbound()
        XCTAssertEqual("", outputBuffer?.readString(length: 0))
        XCTAssertFalse(try channel.finish())
    }
    
    func testEmptyBuffer() throws {
        let channel = EmbeddedChannel()
        try channel.pipeline.add(handler: LineBasedFrameDecoder()).wait()
        var buffer = channel.allocator.buffer(capacity: 1)
        buffer.write(string: "")
        XCTAssertFalse(try channel.writeInbound(buffer))
        XCTAssertFalse(try channel.finish())
    }
}
