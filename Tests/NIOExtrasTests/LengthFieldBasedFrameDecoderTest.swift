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
    private var decoderUnderTest: ByteToMessageHandler<LengthFieldBasedFrameDecoder>!
    
    override func setUp() {
        self.channel = EmbeddedChannel()
    }

    func testDecodeWithUInt8HeaderWithData() throws {
        
        self.decoderUnderTest = .init(LengthFieldBasedFrameDecoder(lengthFieldLength: .one,
                                                                   lengthFieldEndianness: .little))
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(self.decoderUnderTest).wait())

        let dataBytes: [UInt8] = [10, 20, 30, 40]
        let dataBytesLengthHeader = UInt8(dataBytes.count)
        
        var buffer = self.channel.allocator.buffer(capacity: 5)
        buffer.writeBytes([dataBytesLengthHeader])
        buffer.writeBytes(dataBytes)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)
        
        XCTAssertNoThrow(XCTAssertEqual(dataBytes,
                                        try self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView.map {
                                            $0
                                        }))
        XCTAssertTrue(try self.channel.finish().isClean)
    }
    
    func testDecodeWithUInt16HeaderWithString() throws {
        
        self.decoderUnderTest = .init(LengthFieldBasedFrameDecoder(lengthFieldLength: .two,
                                                                   lengthFieldEndianness: .little))
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(self.decoderUnderTest).wait())

        let dataLength: UInt16 = 5
        
        var buffer = self.channel.allocator.buffer(capacity: 7) // 2 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .little, as: UInt16.self)
        buffer.writeString(standardDataString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)
        
        XCTAssertNoThrow(XCTAssertEqual(standardDataString,
                                        try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                                            String(decoding: $0, as: Unicode.UTF8.self)
                                        }))
        XCTAssertTrue(try self.channel.finish().isClean)
    }
    
    func testDecodeWithUInt32HeaderWithString() throws {
        
        self.decoderUnderTest = .init(LengthFieldBasedFrameDecoder(lengthFieldLength: .four,
                                                                   lengthFieldEndianness: .little))
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(self.decoderUnderTest).wait())

        let dataLength: UInt32 = 5
        
        var buffer = self.channel.allocator.buffer(capacity: 9) // 4 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .little, as: UInt32.self)
        buffer.writeString(standardDataString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)
        
        XCTAssertNoThrow(XCTAssertEqual(standardDataString,
                                        try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                                            String(decoding: $0, as: Unicode.UTF8.self)
                                        }))
        XCTAssertTrue(try self.channel.finish().isClean)
    }
    
    func testDecodeWithUInt64HeaderWithString() throws {
        
        self.decoderUnderTest = .init(LengthFieldBasedFrameDecoder(lengthFieldLength: .eight,
                                                                   lengthFieldEndianness: .little))
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(self.decoderUnderTest).wait())

        let dataLength: UInt64 = 5
        
        var buffer = self.channel.allocator.buffer(capacity: 13) // 8 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .little, as: UInt64.self)
        buffer.writeString(standardDataString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)
        
        XCTAssertNoThrow(XCTAssertEqual(standardDataString,
                                        try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                                            String(decoding: $0, as: Unicode.UTF8.self)
                                        }))
        XCTAssertTrue(try self.channel.finish().isClean)
    }
    
    func testDecodeWithInt64HeaderWithString() throws {
        
        self.decoderUnderTest = .init(LengthFieldBasedFrameDecoder(lengthFieldLength: .eight,
                                                                   lengthFieldEndianness: .little))
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(self.decoderUnderTest).wait())

        let dataLength: Int64 = 5
        
        var buffer = self.channel.allocator.buffer(capacity: 13) // 8 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .little, as: Int64.self)
        buffer.writeString(standardDataString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)
        
        XCTAssertNoThrow(XCTAssertEqual(standardDataString,
                                        try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                                            String(decoding: $0, as: Unicode.UTF8.self)
                                        }))

        XCTAssertTrue(try self.channel.finish().isClean)
    }
    
    func testDecodeWithInt64HeaderStringBigEndian() throws {
        
        self.decoderUnderTest = .init(LengthFieldBasedFrameDecoder(lengthFieldLength: .eight,
                                                                   lengthFieldEndianness: .big))
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(self.decoderUnderTest).wait())

        let dataLength: Int64 = 5
        
        var buffer = self.channel.allocator.buffer(capacity: 13) // 8 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .big, as: Int64.self)
        buffer.writeString(standardDataString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)
        
        XCTAssertNoThrow(XCTAssertEqual(standardDataString,
                                        try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                                            String(decoding: $0, as: Unicode.UTF8.self)
                                        }))

        XCTAssertTrue(try self.channel.finish().isClean)
    }
    
    func testDecodeWithInt64HeaderStringDefaultingToBigEndian() throws {
        
        self.decoderUnderTest = .init(LengthFieldBasedFrameDecoder(lengthFieldLength: .eight))
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(self.decoderUnderTest).wait())

        let dataLength: Int64 = 5
        
        var buffer = self.channel.allocator.buffer(capacity: 13) // 8 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .big, as: Int64.self)
        buffer.writeString(standardDataString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)
        
        XCTAssertNoThrow(XCTAssertEqual(standardDataString,
                                        try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                                            String(decoding: $0, as: Unicode.UTF8.self)
                                        }))
        XCTAssertTrue(try self.channel.finish().isClean)
    }
    
    func testDecodeWithUInt8HeaderTwoFrames() throws {
        
        self.decoderUnderTest = .init(LengthFieldBasedFrameDecoder(lengthFieldLength: .one,
                                                                   lengthFieldEndianness: .little))
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(self.decoderUnderTest).wait())

        let firstFrameDataLength: UInt8 = 5
        let secondFrameDataLength: UInt8 = 3
        let secondFrameString = "123"
        
        var buffer = self.channel.allocator.buffer(capacity: 10) // 1 byte header + 5 character string + 1 byte header + 3 character string
        buffer.writeInteger(firstFrameDataLength, endianness: .little, as: UInt8.self)
        buffer.writeString(standardDataString)
        buffer.writeInteger(secondFrameDataLength, endianness: .little, as: UInt8.self)
        buffer.writeString(secondFrameString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)
        XCTAssertNoThrow(XCTAssertEqual(standardDataString,
                                        try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                                            String(decoding: $0, as: Unicode.UTF8.self)
            }))

        XCTAssertNoThrow(XCTAssertEqual(secondFrameString,
                                        try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                                            String(decoding: $0, as: Unicode.UTF8.self)
            }))

        XCTAssertTrue(try self.channel.finish().isClean)
    }
    
    func testDecodeWithUInt8HeaderFrameSplitIncomingData() throws {
        
        self.decoderUnderTest = .init(LengthFieldBasedFrameDecoder(lengthFieldLength: .two,
                                                                   lengthFieldEndianness: .little))
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(self.decoderUnderTest).wait())

        let frameDataLength: UInt16 = 5

        // Write and try to read both bytes of the data individually
        let frameDataLengthFirstByte: UInt8 = UInt8(frameDataLength)
        let frameDataLengthSecondByte: UInt8 = 0
        
        var firstBuffer = self.channel.allocator.buffer(capacity: 1) // Byte 1 of 2 byte header header
        firstBuffer.writeInteger(frameDataLengthFirstByte, endianness: .little, as: UInt8.self)
        
        XCTAssertTrue(try self.channel.writeInbound(firstBuffer).isEmpty)
        
        // Read should fail because there is not yet enough data.
        XCTAssertNoThrow(XCTAssertNil(try self.channel.readInbound()))
        
        var secondBuffer = self.channel.allocator.buffer(capacity: 1) // Byte 2 of 2 byte header header
        secondBuffer.writeInteger(frameDataLengthSecondByte, endianness: .little, as: UInt8.self)
        
        XCTAssertTrue(try self.channel.writeInbound(secondBuffer).isEmpty)
        
        // Read should fail because there is not yet enough data.
        XCTAssertNoThrow(XCTAssertNil(try self.channel.readInbound()))
        
        // Write and try to read each byte of the data individually
        for (index, character) in standardDataString.enumerated() {
            
            var characterBuffer = self.channel.allocator.buffer(capacity: 1)
            characterBuffer.writeString(String(character))
            
            if index < standardDataString.count - 1 {
                
                XCTAssertTrue(try self.channel.writeInbound(characterBuffer).isEmpty)
                // Read should fail because there is not yet enough data.
                XCTAssertNoThrow(XCTAssertNil(try self.channel.readInbound()))
            } else {
                XCTAssertTrue(try self.channel.writeInbound(characterBuffer).isFull)
            }
        }
        
        XCTAssertNoThrow(XCTAssertEqual(standardDataString,
                                        try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                                            String(decoding: $0, as: Unicode.UTF8.self)
            }))
        XCTAssertTrue(try self.channel.finish().isClean)
    }
    
    func testEmptyBuffer() throws {
        
        self.decoderUnderTest = .init(LengthFieldBasedFrameDecoder(lengthFieldLength: .one,
                                                                   lengthFieldEndianness: .little))
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(self.decoderUnderTest).wait())

        let buffer = self.channel.allocator.buffer(capacity: 1)
        XCTAssertTrue(try self.channel.writeInbound(buffer).isEmpty)
        XCTAssertTrue(try self.channel.finish().isClean)
    }
    
    func testDecodeWithUInt16HeaderWithPartialHeader() throws {
        
        self.decoderUnderTest = .init(LengthFieldBasedFrameDecoder(lengthFieldLength: .two,
                                                                   lengthFieldEndianness: .little))
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(self.decoderUnderTest).wait())
        
        let dataLength: UInt8 = 5 // 8 byte is only half the length required
        
        var buffer = self.channel.allocator.buffer(capacity: 7) // 2 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .little, as: UInt8.self)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer).isEmpty)
        XCTAssertThrowsError(try channel.finish()) { error in
            if let error = error as? NIOExtrasErrors.LeftOverBytesError {
                XCTAssertEqual(1 /* just the one byte of the length that arrived */, error.leftOverBytes.readableBytes)
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
    }
    
    func testDecodeWithUInt16HeaderWithPartialBody() throws {
        
        self.decoderUnderTest = .init(LengthFieldBasedFrameDecoder(lengthFieldLength: .two,
                                                                   lengthFieldEndianness: .little))
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(self.decoderUnderTest).wait())

        let dataLength: UInt16 = 7
        
        var buffer = self.channel.allocator.buffer(capacity: 9) // 2 byte header + 7 character string
        buffer.writeInteger(dataLength, endianness: .little, as: UInt16.self)
        buffer.writeString(standardDataString) // 2 bytes short of the 7 required.
        
        XCTAssertTrue(try self.channel.writeInbound(buffer).isEmpty)
        XCTAssertThrowsError(try channel.finish()) { error in
            if let error = error as? NIOExtrasErrors.LeftOverBytesError {
                XCTAssertEqual(Int(dataLength) - 2 /* we're 2 bytes short of the required 7 */,
                               error.leftOverBytes.readableBytes)
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
    }
    
    func testRemoveHandlerWhenBufferIsEmpty() throws {
        
        self.decoderUnderTest = .init(LengthFieldBasedFrameDecoder(lengthFieldLength: .eight,
                                                                   lengthFieldEndianness: .little))
        try? self.channel.pipeline.addHandler(self.decoderUnderTest).wait()
        
        let dataLength: Int64 = 5
        
        var buffer = self.channel.allocator.buffer(capacity: 13) // 8 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .little, as: Int64.self)
        buffer.writeString(standardDataString)
        
        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)
        
        let removeFuture = self.channel.pipeline.removeHandler(self.decoderUnderTest)
        (channel.eventLoop as! EmbeddedEventLoop).run()
        XCTAssertNoThrow(try removeFuture.wait())

        
        XCTAssertNoThrow(XCTAssertEqual(standardDataString,
                                        try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                                            String(decoding: $0, as: Unicode.UTF8.self)
            }))
        XCTAssertNoThrow(try self.channel.throwIfErrorCaught())
        XCTAssertTrue(try self.channel.finish().isClean)
    }
    
    func testRemoveHandlerWhenBufferIsNotEmpty() throws {
        
        self.decoderUnderTest = .init(LengthFieldBasedFrameDecoder(lengthFieldLength: .eight,
                                                                   lengthFieldEndianness: .little))
        try? self.channel.pipeline.addHandler(self.decoderUnderTest).wait()
        
        let extraUnusedDataString = "fghi"
        let dataLength: Int64 = 5

        var buffer = self.channel.allocator.buffer(capacity: 17) // 8 byte header + 5 character string + 4 unused
        buffer.writeInteger(dataLength, endianness: .little, as: Int64.self)
        buffer.writeString(standardDataString + extraUnusedDataString)
        
        XCTAssertTrue(try channel.writeInbound(buffer).isFull)
        
        let removeFuture = self.channel.pipeline.removeHandler(self.decoderUnderTest)
        (channel.eventLoop as! EmbeddedEventLoop).run()
        XCTAssertNoThrow(try removeFuture.wait())
        
        XCTAssertThrowsError(try self.channel.throwIfErrorCaught()) { error in
            guard let error = error as? NIOExtrasErrors.LeftOverBytesError else {
                XCTFail()
                return
            }
            
            var expectedBuffer = self.channel.allocator.buffer(capacity: 7)
            expectedBuffer.writeString(extraUnusedDataString)
            XCTAssertEqual(error.leftOverBytes, expectedBuffer)
        }
        
        XCTAssertNoThrow(XCTAssertEqual(standardDataString,
                                        try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                                            String(decoding: $0, as: Unicode.UTF8.self)
            }))
        XCTAssertTrue(try self.channel.finish().isClean)
    }
}
