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

class LengthFieldBasedFrameDecoderTest: XCTestCase {
    
    private var channel: EmbeddedChannel!
    private var decoderUnderTest: LengthFieldBasedFrameDecoder!
    
    override func setUp() {
        self.channel = EmbeddedChannel()
    }

    func testDecodeWithUInt8HeaderWithData() throws {
        
        self.decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: .one,  lengthFieldEndianness: .little)
        try? self.channel.pipeline.add(handler: self.decoderUnderTest).wait()
        
        let dataBytes: [UInt8] = [10, 20, 30, 40]
        let dataBytesLengthHeader = UInt8(dataBytes.count)
        
        var buffer = self.channel.allocator.buffer(capacity: 5)
        buffer.write(bytes: [dataBytesLengthHeader])
        buffer.write(bytes: dataBytes)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = self.channel.readInbound()
        let outputData = outputBuffer?.readBytes(length: dataBytes.count)
        
        XCTAssertEqual(dataBytes, outputData)
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testDecodeWithUInt16HeaderWithString() throws {
        
        self.decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: .two,  lengthFieldEndianness: .little)
        try? self.channel.pipeline.add(handler: self.decoderUnderTest).wait()
        
        let dataLength: UInt16 = 5
        
        var buffer = self.channel.allocator.buffer(capacity: 7) // 2 byte header + 5 character string
        buffer.write(integer: dataLength, endianness: .little, as: UInt16.self)
        buffer.write(string: standardDataString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = self.channel.readInbound()
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        
        XCTAssertEqual(standardDataString, outputData)
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testDecodeWithUInt32HeaderWithString() throws {
        
        self.decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: .four,  lengthFieldEndianness: .little)
        try? self.channel.pipeline.add(handler: self.decoderUnderTest).wait()
        
        let dataLength: UInt32 = 5
        
        var buffer = self.channel.allocator.buffer(capacity: 9) // 4 byte header + 5 character string
        buffer.write(integer: dataLength, endianness: .little, as: UInt32.self)
        buffer.write(string: standardDataString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = self.channel.readInbound()
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        
        XCTAssertEqual(standardDataString, outputData)
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testDecodeWithUInt64HeaderWithString() throws {
        
        self.decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: .eight,  lengthFieldEndianness: .little)
        try? self.channel.pipeline.add(handler: self.decoderUnderTest).wait()
        
        let dataLength: UInt64 = 5
        
        var buffer = self.channel.allocator.buffer(capacity: 13) // 8 byte header + 5 character string
        buffer.write(integer: dataLength, endianness: .little, as: UInt64.self)
        buffer.write(string: standardDataString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = self.channel.readInbound()
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        
        XCTAssertEqual(standardDataString, outputData)
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testDecodeWithInt64HeaderWithString() throws {
        
        self.decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: .eight,  lengthFieldEndianness: .little)
        try? self.channel.pipeline.add(handler: self.decoderUnderTest).wait()
        
        let dataLength: Int64 = 5
        
        var buffer = self.channel.allocator.buffer(capacity: 13) // 8 byte header + 5 character string
        buffer.write(integer: dataLength, endianness: .little, as: Int64.self)
        buffer.write(string: standardDataString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = self.channel.readInbound()
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        
        XCTAssertEqual(standardDataString, outputData)
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testDecodeWithInt64HeaderStringBigEndian() throws {
        
        self.decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: .eight,  lengthFieldEndianness: .big)
        try? self.channel.pipeline.add(handler: self.decoderUnderTest).wait()
        
        let dataLength: Int64 = 5
        
        var buffer = self.channel.allocator.buffer(capacity: 13) // 8 byte header + 5 character string
        buffer.write(integer: dataLength, endianness: .big, as: Int64.self)
        buffer.write(string: standardDataString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = self.channel.readInbound()
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        
        XCTAssertEqual(standardDataString, outputData)
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testDecodeWithInt64HeaderStringDefaultingToBigEndian() throws {
        
        self.decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: .eight)
        try? self.channel.pipeline.add(handler: self.decoderUnderTest).wait()
        
        let dataLength: Int64 = 5
        
        var buffer = self.channel.allocator.buffer(capacity: 13) // 8 byte header + 5 character string
        buffer.write(integer: dataLength, endianness: .big, as: Int64.self)
        buffer.write(string: standardDataString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = self.channel.readInbound()
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        
        XCTAssertEqual(standardDataString, outputData)
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testDecodeWithUInt8HeaderTwoFrames() throws {
        
        self.decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: .one,  lengthFieldEndianness: .little)
        try? self.channel.pipeline.add(handler: self.decoderUnderTest).wait()
        
        let firstFrameDataLength: UInt8 = 5
        let secondFrameDataLength: UInt8 = 3
        let secondFrameString = "123"
        
        var buffer = self.channel.allocator.buffer(capacity: 10) // 1 byte header + 5 character string + 1 byte header + 3 character string
        buffer.write(integer: firstFrameDataLength, endianness: .little, as: UInt8.self)
        buffer.write(string: standardDataString)
        buffer.write(integer: secondFrameDataLength, endianness: .little, as: UInt8.self)
        buffer.write(string: secondFrameString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        var outputFirstFrameBuffer: ByteBuffer? = self.channel.readInbound()
        
        let outputFirstFrameData = outputFirstFrameBuffer?.readString(length: standardDataString.count)
        XCTAssertEqual(standardDataString, outputFirstFrameData)
        
        var outputSecondFrameBuffer: ByteBuffer? = self.channel.readInbound()
        
        let outputSecondFrameData = outputSecondFrameBuffer?.readString(length: secondFrameString.count)
        XCTAssertEqual(secondFrameString, outputSecondFrameData)
        
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testDecodeWithUInt8HeaderFrameSplitIncomingData() throws {
        
        self.decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: .one,  lengthFieldEndianness: .little)
        try? self.channel.pipeline.add(handler: self.decoderUnderTest).wait()
    
        let frameDataLength: UInt8 = 5
        
        var firstBuffer = self.channel.allocator.buffer(capacity: 1) // 1 byte header
        firstBuffer.write(integer: frameDataLength, endianness: .little, as: UInt8.self)
        
        XCTAssertFalse(try self.channel.writeInbound(firstBuffer))
        
        // Read should fail because there is not yet enough data.
        XCTAssertNil(self.channel.readInbound())
        
        var secondBuffer = self.channel.allocator.buffer(capacity: 5) // 5 byte data
        secondBuffer.write(string: standardDataString)
        
        XCTAssertTrue(try self.channel.writeInbound(secondBuffer))
        
        var outputBuffer: ByteBuffer? = self.channel.readInbound()
        
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        XCTAssertEqual(standardDataString, outputData)

        XCTAssertFalse(try self.channel.finish())
    }
    
    func testEmptyBuffer() throws {
        
        self.decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: .one,  lengthFieldEndianness: .little)
        try? self.channel.pipeline.add(handler: self.decoderUnderTest).wait()
        
        let buffer = self.channel.allocator.buffer(capacity: 1)
        XCTAssertFalse(try self.channel.writeInbound(buffer))
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testDecodeWithUInt16HeaderWithPartialHeader() throws {
        
        self.decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: .two,  lengthFieldEndianness: .little)
        try? self.channel.pipeline.add(handler: self.decoderUnderTest).wait()
        
        let dataLength: UInt8 = 5 // 8 byte is only half the length required
        
        var buffer = self.channel.allocator.buffer(capacity: 7) // 2 byte header + 5 character string
        buffer.write(integer: dataLength, endianness: .little, as: UInt8.self)
        
        XCTAssertFalse(try self.channel.writeInbound(buffer))
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testDecodeWithUInt16HeaderWithPartialBody() throws {
        
        self.decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: .two,  lengthFieldEndianness: .little)
        try? self.channel.pipeline.add(handler: self.decoderUnderTest).wait()
        
        let dataLength: UInt16 = 7
        
        var buffer = self.channel.allocator.buffer(capacity: 9) // 2 byte header + 7 character string
        buffer.write(integer: dataLength, endianness: .little, as: UInt16.self)
        buffer.write(string: standardDataString) // 2 bytes short of the 7 required.
        
        XCTAssertFalse(try self.channel.writeInbound(buffer))
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testRemoveHandlerWhenBufferIsEmpty() throws {
        
        self.decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: .eight,  lengthFieldEndianness: .little)
        try? self.channel.pipeline.add(handler: self.decoderUnderTest).wait()
        
        let dataLength: Int64 = 5
        
        var buffer = self.channel.allocator.buffer(capacity: 13) // 8 byte header + 5 character string
        buffer.write(integer: dataLength, endianness: .little, as: Int64.self)
        buffer.write(string: standardDataString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = self.channel.readInbound()
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        
        _ = try self.channel.pipeline.remove(handler: self.decoderUnderTest).wait()
        
        XCTAssertEqual(standardDataString, outputData)
        XCTAssertNoThrow(try self.channel.throwIfErrorCaught())
        XCTAssertFalse(try self.channel.finish())
    }
    
    func testRemoveHandlerWhenBufferIsNotEmpty() throws {
        
        self.decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: .eight,  lengthFieldEndianness: .little)
        try? self.channel.pipeline.add(handler: self.decoderUnderTest).wait()
        
        let extraUnusedDataString = "fghi"
        let dataLength: Int64 = 5

        var buffer = self.channel.allocator.buffer(capacity: 17) // 8 byte header + 5 character string + 4 unused
        buffer.write(integer: dataLength, endianness: .little, as: Int64.self)
        buffer.write(string: standardDataString + extraUnusedDataString)
        
        XCTAssertTrue(try channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = self.channel.readInbound()
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        
        _ = try self.channel.pipeline.remove(handler: self.decoderUnderTest).wait()
        
        XCTAssertThrowsError(try self.channel.throwIfErrorCaught()) { error in
    
            guard let error = error as? NIOExtrasErrors.LeftOverBytesError else {
                XCTFail()
                return
            }
            
            var expectedBuffer = self.channel.allocator.buffer(capacity: 7)
            expectedBuffer.write(string: extraUnusedDataString)
            XCTAssertEqual(error.leftOverBytes, expectedBuffer)
        }
        
        XCTAssertEqual(standardDataString, outputData)
        XCTAssertFalse(try self.channel.finish())
    }
}
