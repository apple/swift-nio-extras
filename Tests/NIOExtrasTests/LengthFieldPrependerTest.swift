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
        let extepectedData: [UInt8] = [UInt8(dataBytes.count)] + dataBytes
        
        var buffer = self.channel.allocator.buffer(capacity: dataBytes.count)
        buffer.write(bytes: dataBytes)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let outputData = outputBuffer.readBytes(length: outputBuffer.readableBytes)
            XCTAssertEqual(extepectedData,  outputData)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEncodeWithUInt16HeaderWithString() throws {
        
        let endianness: Endianness = .little
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .two,
                                                     lengthFieldEndianness: endianness)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        var buffer = self.channel.allocator.buffer(capacity: standardDataString.count)
        buffer.write(string: standardDataString)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt16.self).map({ Int($0) })
            XCTAssertEqual(standardDataString.count, sizeInHeader)
            
            let bodyString = outputBuffer.readString(length: standardDataString.count)
            XCTAssertEqual(standardDataString, bodyString)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEncodeWithUInt32HeaderWithString() throws {
        
        let endianness: Endianness = .little
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .four,
                                                     lengthFieldEndianness: endianness)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        var buffer = self.channel.allocator.buffer(capacity: standardDataString.count)
        buffer.write(string: standardDataString)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt32.self).map({ Int($0) })
            XCTAssertEqual(standardDataString.count, sizeInHeader)
            
            let bodyString = outputBuffer.readString(length: standardDataString.count)
            XCTAssertEqual(standardDataString, bodyString)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEncodeWithUInt64HeaderWithString() throws {
        
        let endianness: Endianness = .little
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .eight,
                                                     lengthFieldEndianness: endianness)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        var buffer = self.channel.allocator.buffer(capacity: standardDataString.count)
        buffer.write(string: standardDataString)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt64.self).map({ Int($0) })
            XCTAssertEqual(standardDataString.count, sizeInHeader)
            
            let bodyString = outputBuffer.readString(length: standardDataString.count)
            XCTAssertEqual(standardDataString, bodyString)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEncodeWithInt64HeaderWithString() throws {
        
        let endianness: Endianness = .little
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .eight,
                                                     lengthFieldEndianness: endianness)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        var buffer = self.channel.allocator.buffer(capacity: standardDataString.count)
        buffer.write(string: standardDataString)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: Int64.self).map({ Int($0) })
            XCTAssertEqual(standardDataString.count, sizeInHeader)
            
            let bodyString = outputBuffer.readString(length: standardDataString.count)
            XCTAssertEqual(standardDataString, bodyString)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEncodeWithUInt64HeaderStringBigEndian() throws {
        
        let endianness: Endianness = .big
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .eight,
                                                     lengthFieldEndianness: endianness)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        var buffer = self.channel.allocator.buffer(capacity: standardDataString.count)
        buffer.write(string: standardDataString)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt64.self).map({ Int($0) })
            XCTAssertEqual(standardDataString.count, sizeInHeader)
            
            let bodyString = outputBuffer.readString(length: standardDataString.count)
            XCTAssertEqual(standardDataString, bodyString)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEncodeWithInt64HeaderStringDefaultingToBigEndian() throws {
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .eight)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        var buffer = self.channel.allocator.buffer(capacity: standardDataString.count)
        buffer.write(string: standardDataString)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let sizeInHeader = outputBuffer.readInteger(endianness: .big, as: UInt64.self).map({ Int($0) })
            XCTAssertEqual(standardDataString.count, sizeInHeader)
            
            let bodyString = outputBuffer.readString(length: standardDataString.count)
            XCTAssertEqual(standardDataString, bodyString)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
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
        
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testTooLargeFor256DefaultBuffer() throws {
        
        // Default implementation of 'MessageToByteEncoder' allocates a `ByteBuffer` with capacity of `256`
        
        let endianness: Endianness = .little
        
        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .eight,
                                                     lengthFieldEndianness: endianness)
        
        try? self.channel.pipeline.add(handler: self.encoderUnderTest).wait()
        
        let contents = Array<UInt8>(repeating: 200, count: 256)
        
        var buffer = self.channel.allocator.buffer(capacity: contents.count)
        buffer.write(bytes: contents)
        
        try self.channel.writeAndFlush(buffer).wait()
        
        if case .some(.byteBuffer(var outputBuffer)) = self.channel.readOutbound() {
            
            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt64.self).map({ Int($0) })
            XCTAssertEqual(contents.count, sizeInHeader)
            
            let bodyData = outputBuffer.readBytes(length: contents.count)
            XCTAssertEqual(contents, bodyData)
            
            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)
            
        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }
        
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
            XCTFail("Did not throw LengthFieldPrependerError.messageDataTooLongForLengthField")
        } catch LengthFieldPrependerError.messageDataTooLongForLengthField {
            
        } catch {
            XCTFail("Threw incorrect error: \(error) expecting LengthFieldPrependerError.messageDataTooLongForLengthField")
        }

        XCTAssertFalse(try self.channel.finish())
    }
}
