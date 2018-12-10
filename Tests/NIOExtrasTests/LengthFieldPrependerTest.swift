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

private let standardDataString = "abcde"
private let standardDataStringCount = standardDataString.utf8.count

class LengthFieldPrependerTest: XCTestCase {
    
    private var channel: EmbeddedChannel!
    private var encoderUnderTest: LengthFieldPrepender!
    
    override func setUp() {
        self.channel = EmbeddedChannel()
    }

    func testEncodeWithUInt8HeaderWithData() throws {
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .one,
                                                     lengthFieldEndianness: .little)

        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        let dataBytes: [UInt8] = [10, 20, 30, 40]
        
        var buffer = self.channel.allocator.buffer(capacity: dataBytes.count)
        buffer.write(bytes: dataBytes)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var headerBuffer)) = self.channel.readOutbound() {
            
            let outputData = headerBuffer.readBytes(length: headerBuffer.readableBytes)
            XCTAssertEqual([UInt8(dataBytes.count)],  outputData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let outputData = outputBuffer.readBytes(length: outputBuffer.readableBytes)
            XCTAssertEqual(dataBytes,  outputData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        XCTAssertNil(self.channel.readOutbound())
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEncodeWithUInt16HeaderWithString() throws {
        
        let endianness: Endianness = .little
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .two,
                                                     lengthFieldEndianness: endianness)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        var buffer = self.channel.allocator.buffer(capacity: standardDataStringCount)
        buffer.write(string: standardDataString)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt16.self).map({ Int($0) })
            XCTAssertEqual(standardDataStringCount, sizeInHeader)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let bodyString = outputBuffer.readString(length: standardDataString.count)
            XCTAssertEqual(standardDataString, bodyString)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        XCTAssertNil(self.channel.readOutbound())
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEncodeWithUInt32HeaderWithString() throws {
        
        let endianness: Endianness = .little
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .four,
                                                     lengthFieldEndianness: endianness)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        var buffer = self.channel.allocator.buffer(capacity: standardDataStringCount)
        buffer.write(string: standardDataString)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt32.self).map({ Int($0) })
            XCTAssertEqual(standardDataStringCount, sizeInHeader)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let bodyString = outputBuffer.readString(length: standardDataStringCount)
            XCTAssertEqual(standardDataString, bodyString)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        XCTAssertNil(self.channel.readOutbound())
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEncodeWithUInt64HeaderWithString() throws {
        
        let endianness: Endianness = .little
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .eight,
                                                     lengthFieldEndianness: endianness)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        var buffer = self.channel.allocator.buffer(capacity: standardDataStringCount)
        buffer.write(string: standardDataString)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt64.self).map({ Int($0) })
            XCTAssertEqual(standardDataStringCount, sizeInHeader)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let bodyString = outputBuffer.readString(length: outputBuffer.readableBytes)
            XCTAssertEqual(standardDataString, bodyString)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        XCTAssertNil(self.channel.readOutbound())
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEncodeWithInt64HeaderWithString() throws {
        
        let endianness: Endianness = .little
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .eight,
                                                     lengthFieldEndianness: endianness)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        var buffer = self.channel.allocator.buffer(capacity: standardDataStringCount)
        buffer.write(string: standardDataString)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: Int64.self).map({ Int($0) })
            XCTAssertEqual(standardDataStringCount, sizeInHeader)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {

            let bodyString = outputBuffer.readString(length: standardDataStringCount)
            XCTAssertEqual(standardDataString, bodyString)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
       XCTAssertNil(self.channel.readOutbound())
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEncodeWithUInt64HeaderStringBigEndian() throws {
        
        let endianness: Endianness = .big
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .eight,
                                                     lengthFieldEndianness: endianness)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        var buffer = self.channel.allocator.buffer(capacity: standardDataStringCount)
        buffer.write(string: standardDataString)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt64.self).map({ Int($0) })
            XCTAssertEqual(standardDataStringCount, sizeInHeader)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {

            let bodyString = outputBuffer.readString(length: standardDataStringCount)
            XCTAssertEqual(standardDataString, bodyString)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        XCTAssertNil(self.channel.readOutbound())
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEncodeWithInt64HeaderStringDefaultingToBigEndian() throws {
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .eight)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        var buffer = self.channel.allocator.buffer(capacity: standardDataStringCount)
        buffer.write(string: standardDataString)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let sizeInHeader = outputBuffer.readInteger(endianness: .big, as: UInt64.self).map({ Int($0) })
            XCTAssertEqual(standardDataStringCount, sizeInHeader)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let bodyString = outputBuffer.readString(length: standardDataStringCount)
            XCTAssertEqual(standardDataString, bodyString)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        XCTAssertNil(self.channel.readOutbound())
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEmptyBuffer() throws {
        
        let endianness: Endianness = .little
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .eight,
                                                     lengthFieldEndianness: endianness)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        let buffer = self.channel.allocator.buffer(capacity: 0)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt64.self).map({ Int($0) })
            XCTAssertEqual(0, sizeInHeader)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        // Check that if there is any more buffer it has a zero size.
        if case .some(.byteBuffer(let outputBuffer)) = self.channel.readOutbound() {
            XCTAssertEqual(0, outputBuffer.readableBytes)
        }
        
        XCTAssertNil(self.channel.readOutbound())
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testLargeBuffer() throws {
        
        let endianness: Endianness = .little
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .eight,
                                                     lengthFieldEndianness: endianness)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        let contents = Array<UInt8>(repeating: 200, count: 514)
        
        var buffer = self.channel.allocator.buffer(capacity: contents.count)
        buffer.write(bytes: contents)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt64.self).map({ Int($0) })
            XCTAssertEqual(contents.count, sizeInHeader)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {

            let bodyData = outputBuffer.readBytes(length: outputBuffer.readableBytes)
            XCTAssertEqual(contents, bodyData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        XCTAssertNil(self.channel.readOutbound())
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testTooLargeForLengthField() throws {
        
        let endianness: Endianness = .little

        // One byte has maximum integer description of 256
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .one,
                                                     lengthFieldEndianness: endianness)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        let contents = Array<UInt8>(repeating: 200, count: 300)
        
        var buffer = self.channel.allocator.buffer(capacity: contents.count)
        buffer.write(bytes: contents)
        
        do {
            try self.channel.writeAndFlush(buffer).wait()
        } catch {
            XCTAssertEqual(LengthFieldPrependerError.messageDataTooLongForLengthField,
                           error as? LengthFieldPrependerError)
        }
        
        XCTAssertNil(self.channel.readOutbound())
        XCTAssertFalse(try self.channel.finish())
    }
}
