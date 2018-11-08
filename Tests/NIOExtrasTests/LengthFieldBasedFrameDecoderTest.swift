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
        channel = EmbeddedChannel()
    }

    func testDecodeWithUInt8HeaderWithData() throws {
        
        decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: 1)
        try? channel.pipeline.add(handler: decoderUnderTest).wait()
        
        let dataBytes: [UInt8] = [10, 20, 30, 40]
        let dataBytesLengthHeader = UInt8(dataBytes.count)
        
        var buffer = channel.allocator.buffer(capacity: 5)
        buffer.write(bytes: [dataBytesLengthHeader])
        buffer.write(bytes: dataBytes)
        
        XCTAssertTrue(try channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = channel.readInbound()
        let outputData = outputBuffer?.readBytes(length: dataBytes.count)
        
        XCTAssertEqual(dataBytes, outputData)
        XCTAssertFalse(try channel.finish())
    }
    
    func testDecodeWithUInt8HeaderWithString() throws {
        
        decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: 1)
        try? channel.pipeline.add(handler: decoderUnderTest).wait()
        
        var dataLength: UInt8 = 5
        
        let headerData = Data(bytes: &dataLength, count: MemoryLayout.size(ofValue: dataLength))
        
        var buffer = channel.allocator.buffer(capacity: 6)
        buffer.write(bytes: headerData)
        buffer.write(string: standardDataString)
        
        XCTAssertTrue(try channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = channel.readInbound()
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        
        XCTAssertEqual(standardDataString, outputData)
        XCTAssertFalse(try channel.finish())
    }
    
    func testDecodeWithUInt16HeaderWithString() throws {
        
        decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: 2)
        try? channel.pipeline.add(handler: decoderUnderTest).wait()
        
        var dataLength: UInt16 = 5
        
        let headerData = Data(bytes: &dataLength, count: MemoryLayout.size(ofValue: dataLength))
        
        var buffer = channel.allocator.buffer(capacity: 7) // 2 byte header + 5 character string
        buffer.write(bytes: headerData)
        buffer.write(string: standardDataString)
        
        XCTAssertTrue(try channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = channel.readInbound()
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        
        XCTAssertEqual(standardDataString, outputData)
        XCTAssertFalse(try channel.finish())
    }
    
    func testDecodeWithUInt32HeaderWithString() throws {
        
        decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: 4)
        try? channel.pipeline.add(handler: decoderUnderTest).wait()
        
        var dataLength: UInt32 = 5
        
        let headerData = Data(bytes: &dataLength, count: MemoryLayout.size(ofValue: dataLength))
        
        var buffer = channel.allocator.buffer(capacity: 9) // 4 byte header + 5 character string
        buffer.write(bytes: headerData)
        buffer.write(string: standardDataString)
        
        XCTAssertTrue(try channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = channel.readInbound()
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        
        XCTAssertEqual(standardDataString, outputData)
        XCTAssertFalse(try channel.finish())
    }
    
    func testDecodeWithUInt64HeaderWithString() throws {
        
        decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: 8)
        try? channel.pipeline.add(handler: decoderUnderTest).wait()
        
        var dataLength: UInt64 = 5
        
        let headerData = Data(bytes: &dataLength, count: MemoryLayout.size(ofValue: dataLength))
        
        var buffer = channel.allocator.buffer(capacity: 13) // 8 byte header + 5 character string
        buffer.write(bytes: headerData)
        buffer.write(string: standardDataString)
        
        XCTAssertTrue(try channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = channel.readInbound()
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        
        XCTAssertEqual(standardDataString, outputData)
        XCTAssertFalse(try channel.finish())
    }
    
    func testDecodeWithInt64HeaderWithString() throws {
        
        decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: 8)
        try? channel.pipeline.add(handler: decoderUnderTest).wait()
        
        var dataLength: Int64 = 5
        
        let headerData = Data(bytes: &dataLength, count: MemoryLayout.size(ofValue: dataLength))
        
        var buffer = channel.allocator.buffer(capacity: 13) // 8 byte header + 5 character string
        buffer.write(bytes: headerData)
        buffer.write(string: standardDataString)
        
        XCTAssertTrue(try channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = channel.readInbound()
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        
        XCTAssertEqual(standardDataString, outputData)
        XCTAssertFalse(try channel.finish())
    }
    
    func testDecodeWithUInt8HeaderTwoFrames() throws {
        
        decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: 1)
        try? channel.pipeline.add(handler: decoderUnderTest).wait()
        
        var firstFrameDataLength: Int8 = 5
        var secondFrameDataLength: Int8 = 3
        let secondFrameString = "123"
        
        let firstFrameHeaderData = Data(bytes: &firstFrameDataLength, count: MemoryLayout.size(ofValue: firstFrameDataLength))
        let secondFrameHeaderData = Data(bytes: &secondFrameDataLength, count: MemoryLayout.size(ofValue: secondFrameDataLength))
        
        var buffer = channel.allocator.buffer(capacity: 10) // 1 byte header + 5 character string + 1 byte header + 3 character string
        buffer.write(bytes: firstFrameHeaderData)
        buffer.write(string: standardDataString)
        buffer.write(bytes: secondFrameHeaderData)
        buffer.write(string: secondFrameString)
        
        XCTAssertTrue(try channel.writeInbound(buffer))
        var outputFirstFrameBuffer: ByteBuffer? = channel.readInbound()
        
        let outputFirstFrameData = outputFirstFrameBuffer?.readString(length: standardDataString.count)
        XCTAssertEqual(standardDataString, outputFirstFrameData)
        
        var outputSecondFrameBuffer: ByteBuffer? = channel.readInbound()
        
        let outputSecondFrameData = outputSecondFrameBuffer?.readString(length: secondFrameString.count)
        XCTAssertEqual(secondFrameString, outputSecondFrameData)
        
        XCTAssertFalse(try channel.finish())
    }
    
    func testEmptyBuffer() throws {
        
        decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: 1)
        try? channel.pipeline.add(handler: decoderUnderTest).wait()
        
        var buffer = channel.allocator.buffer(capacity: 1)
        buffer.write(string: "")
        XCTAssertFalse(try channel.writeInbound(buffer))
        XCTAssertFalse(try channel.finish())
    }
    
    func testDecodeWithUInt16HeaderWithPartialHeader() throws {
        
        decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: 2)
        try? channel.pipeline.add(handler: decoderUnderTest).wait()
        
        var dataLength: UInt8 = 5 // 8 byte is only half the length required
        
        let partialHeaderData = Data(bytes: &dataLength, count: MemoryLayout.size(ofValue: dataLength))
        
        var buffer = channel.allocator.buffer(capacity: 7) // 2 byte header + 5 character string
        buffer.write(bytes: partialHeaderData)
        
        XCTAssertFalse(try channel.writeInbound(buffer))
        XCTAssertFalse(try channel.finish())
    }
    
    func testDecodeWithUInt16HeaderWithPartialBody() throws {
        
        decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: 2)
        try? channel.pipeline.add(handler: decoderUnderTest).wait()
        
        var dataLength: UInt16 = 7
        
        let partialHeaderData = Data(bytes: &dataLength, count: MemoryLayout.size(ofValue: dataLength))
        
        var buffer = channel.allocator.buffer(capacity: 9) // 2 byte header + 7 character string
        buffer.write(bytes: partialHeaderData)
        buffer.write(string: standardDataString) // 2 bytes short of the 7 required.
        
        XCTAssertFalse(try channel.writeInbound(buffer))
        XCTAssertFalse(try channel.finish())
    }
    
    func testRemoveHandlerWhenBufferIsEmpty() throws {
        
        decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: 8)
        try? channel.pipeline.add(handler: decoderUnderTest).wait()
        
        var dataLength: Int64 = 5
        
        let headerData = Data(bytes: &dataLength, count: MemoryLayout.size(ofValue: dataLength))
        
        var buffer = channel.allocator.buffer(capacity: 13) // 8 byte header + 5 character string
        buffer.write(bytes: headerData)
        buffer.write(string: standardDataString)
        
        XCTAssertTrue(try channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = channel.readInbound()
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        
        _ = try channel.pipeline.remove(handler: decoderUnderTest).wait()
        
        XCTAssertEqual(standardDataString, outputData)
        XCTAssertNoThrow(try channel.throwIfErrorCaught())
        XCTAssertFalse(try channel.finish())
    }
    
    func testRemoveHandlerWhenBufferIsNotEmpty() throws {
        
        decoderUnderTest = LengthFieldBasedFrameDecoder(lengthFieldLength: 8)
        try? channel.pipeline.add(handler: decoderUnderTest).wait()
        
        let extraUnusedDataString = "fghi"
        var dataLength: Int64 = 5
        
        let headerData = Data(bytes: &dataLength, count: MemoryLayout.size(ofValue: dataLength))
        
        var buffer = channel.allocator.buffer(capacity: 17) // 8 byte header + 5 character string + 4 unused
        buffer.write(bytes: headerData)
        buffer.write(string: standardDataString + extraUnusedDataString)
        
        XCTAssertTrue(try channel.writeInbound(buffer))
        
        var outputBuffer: ByteBuffer? = channel.readInbound()
        let outputData = outputBuffer?.readString(length: standardDataString.count)
        
        _ = try channel.pipeline.remove(handler: decoderUnderTest).wait()
        
        XCTAssertThrowsError(try channel.throwIfErrorCaught()) { error in
    
            guard let error = error as? NIOExtrasErrors.LeftOverBytesError else {
                XCTFail()
                return
            }
            
            var expectedBuffer = channel.allocator.buffer(capacity: 7)
            expectedBuffer.write(string: extraUnusedDataString)
            XCTAssertEqual(error.leftOverBytes, expectedBuffer)
        }
        
        XCTAssertEqual(standardDataString, outputData)
        XCTAssertFalse(try channel.finish())
    }
}
