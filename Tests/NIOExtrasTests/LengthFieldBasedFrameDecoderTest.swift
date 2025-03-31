//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2021 Apple Inc. and the SwiftNIO project authors
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
import NIOTestUtils
import XCTest

@testable import NIOExtras

private let standardDataString = "abcde"

class LengthFieldBasedFrameDecoderTest: XCTestCase {

    private var channel: EmbeddedChannel!
    private var decoderUnderTest: ByteToMessageHandler<LengthFieldBasedFrameDecoder>!

    override func setUp() {
        self.channel = EmbeddedChannel()
    }
    func testReadUInt32From3Bytes() {
        var buffer = ByteBuffer(bytes: [
            0, 0, 5,
            5, 0, 0,
        ])
        XCTAssertEqual(buffer.read24UInt(endianness: .big), 5)
        print(buffer.readableBytesView)
        XCTAssertEqual(buffer.read24UInt(endianness: .little), 5)
    }
    func testReadAndWriteUInt32From3BytesBasicVerification() {
        let inputs: [UInt32] = [
            0,
            1,
            5,
            UInt32(UInt8.max),
            UInt32(UInt16.max),
            UInt32(UInt16.max) << 8 &+ UInt32(UInt8.max),
            UInt32(UInt8.max) - 1,
            UInt32(UInt16.max) - 1,
            UInt32(UInt16.max) << 8 &+ UInt32(UInt8.max) - 1,
            UInt32(UInt8.max) + 1,
            UInt32(UInt16.max) + 1,
        ]

        for input in inputs {
            var buffer = ByteBuffer()
            buffer.write24UInt(input, endianness: .big)
            XCTAssertEqual(buffer.read24UInt(endianness: .big), input)

            buffer.write24UInt(input, endianness: .little)
            XCTAssertEqual(buffer.read24UInt(endianness: .little), input)
        }
    }

    func testDecodeWithUInt8HeaderWithData() throws {
        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .one,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let dataBytes: [UInt8] = [10, 20, 30, 40]
        let dataBytesLengthHeader = UInt8(dataBytes.count)

        var buffer = self.channel.allocator.buffer(capacity: 5)
        buffer.writeBytes([dataBytesLengthHeader])
        buffer.writeBytes(dataBytes)

        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)

        XCTAssertNoThrow(
            XCTAssertEqual(
                dataBytes,
                try self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView.map {
                    $0
                }
            )
        )
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testDecodeWithUInt16HeaderWithString() throws {

        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .two,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let dataLength: UInt16 = 5

        var buffer = self.channel.allocator.buffer(capacity: 7)  // 2 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .little, as: UInt16.self)
        buffer.writeString(standardDataString)

        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)

        XCTAssertNoThrow(
            XCTAssertEqual(
                standardDataString,
                try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                    String(decoding: $0, as: Unicode.UTF8.self)
                }
            )
        )
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testDecodeWithUInt24HeaderWithString() throws {

        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldBitLength: .threeBytes,
                lengthFieldEndianness: .big
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        var buffer = self.channel.allocator.buffer(capacity: 8)  // 3 byte header + 5 character string
        buffer.writeBytes([0, 0, 5])
        buffer.writeString(standardDataString)

        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)

        XCTAssertNoThrow(
            XCTAssertEqual(
                standardDataString,
                try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                    String(decoding: $0, as: Unicode.UTF8.self)
                }
            )
        )
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testDecodeWithUInt32HeaderWithString() throws {

        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .four,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let dataLength: UInt32 = 5

        var buffer = self.channel.allocator.buffer(capacity: 9)  // 4 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .little, as: UInt32.self)
        buffer.writeString(standardDataString)

        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)

        XCTAssertNoThrow(
            XCTAssertEqual(
                standardDataString,
                try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                    String(decoding: $0, as: Unicode.UTF8.self)
                }
            )
        )
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testDecodeWithUInt64HeaderWithString() throws {

        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .eight,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let dataLength: UInt64 = 5

        var buffer = self.channel.allocator.buffer(capacity: 13)  // 8 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .little, as: UInt64.self)
        buffer.writeString(standardDataString)

        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)

        XCTAssertNoThrow(
            XCTAssertEqual(
                standardDataString,
                try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                    String(decoding: $0, as: Unicode.UTF8.self)
                }
            )
        )
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testDecodeWithInt64HeaderWithString() throws {

        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .eight,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let dataLength: Int64 = 5

        var buffer = self.channel.allocator.buffer(capacity: 13)  // 8 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .little, as: Int64.self)
        buffer.writeString(standardDataString)

        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)

        XCTAssertNoThrow(
            XCTAssertEqual(
                standardDataString,
                try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                    String(decoding: $0, as: Unicode.UTF8.self)
                }
            )
        )

        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testDecodeWithInt64HeaderStringBigEndian() throws {

        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .eight,
                lengthFieldEndianness: .big
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let dataLength: Int64 = 5

        var buffer = self.channel.allocator.buffer(capacity: 13)  // 8 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .big, as: Int64.self)
        buffer.writeString(standardDataString)

        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)

        XCTAssertNoThrow(
            XCTAssertEqual(
                standardDataString,
                try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                    String(decoding: $0, as: Unicode.UTF8.self)
                }
            )
        )

        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testDecodeWithInt64HeaderStringDefaultingToBigEndian() throws {

        self.decoderUnderTest = .init(LengthFieldBasedFrameDecoder(lengthFieldLength: .eight))
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let dataLength: Int64 = 5

        var buffer = self.channel.allocator.buffer(capacity: 13)  // 8 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .big, as: Int64.self)
        buffer.writeString(standardDataString)

        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)

        XCTAssertNoThrow(
            XCTAssertEqual(
                standardDataString,
                try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                    String(decoding: $0, as: Unicode.UTF8.self)
                }
            )
        )
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testDecodeWithUInt8HeaderTwoFrames() throws {

        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .one,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let firstFrameDataLength: UInt8 = 5
        let secondFrameDataLength: UInt8 = 3
        let secondFrameString = "123"

        // 1 byte header + 5 character string + 1 byte header + 3 character string
        var buffer = self.channel.allocator.buffer(capacity: 10)
        buffer.writeInteger(firstFrameDataLength, endianness: .little, as: UInt8.self)
        buffer.writeString(standardDataString)
        buffer.writeInteger(secondFrameDataLength, endianness: .little, as: UInt8.self)
        buffer.writeString(secondFrameString)

        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)
        XCTAssertNoThrow(
            XCTAssertEqual(
                standardDataString,
                try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                    String(decoding: $0, as: Unicode.UTF8.self)
                }
            )
        )

        XCTAssertNoThrow(
            XCTAssertEqual(
                secondFrameString,
                try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                    String(decoding: $0, as: Unicode.UTF8.self)
                }
            )
        )

        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testDecodeWithUInt8HeaderFrameSplitIncomingData() throws {

        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .two,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let frameDataLength: UInt16 = 5

        // Write and try to read both bytes of the data individually
        let frameDataLengthFirstByte: UInt8 = UInt8(frameDataLength)
        let frameDataLengthSecondByte: UInt8 = 0

        var firstBuffer = self.channel.allocator.buffer(capacity: 1)  // Byte 1 of 2 byte header header
        firstBuffer.writeInteger(frameDataLengthFirstByte, endianness: .little, as: UInt8.self)

        XCTAssertTrue(try self.channel.writeInbound(firstBuffer).isEmpty)

        // Read should fail because there is not yet enough data.
        XCTAssertNoThrow(XCTAssertNil(try self.channel.readInbound()))

        var secondBuffer = self.channel.allocator.buffer(capacity: 1)  // Byte 2 of 2 byte header header
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

        XCTAssertNoThrow(
            XCTAssertEqual(
                standardDataString,
                try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                    String(decoding: $0, as: Unicode.UTF8.self)
                }
            )
        )
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testEmptyBuffer() throws {

        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .one,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let buffer = self.channel.allocator.buffer(capacity: 1)
        XCTAssertTrue(try self.channel.writeInbound(buffer).isEmpty)
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testDecodeWithUInt16HeaderWithPartialHeader() throws {

        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .two,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let dataLength: UInt8 = 5  // 8 byte is only half the length required

        var buffer = self.channel.allocator.buffer(capacity: 7)  // 2 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .little, as: UInt8.self)

        XCTAssertTrue(try self.channel.writeInbound(buffer).isEmpty)
        XCTAssertThrowsError(try channel.finish()) { error in
            if let error = error as? NIOExtrasErrors.LeftOverBytesError {
                XCTAssertEqual(1, error.leftOverBytes.readableBytes)  // just the one byte of the length that arrived
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testDecodeWithUInt16HeaderWithPartialBody() throws {

        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .two,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let dataLength: UInt16 = 7

        var buffer = self.channel.allocator.buffer(capacity: 9)  // 2 byte header + 7 character string
        buffer.writeInteger(dataLength, endianness: .little, as: UInt16.self)
        buffer.writeString(standardDataString)  // 2 bytes short of the 7 required.

        XCTAssertTrue(try self.channel.writeInbound(buffer).isEmpty)
        XCTAssertThrowsError(try channel.finish()) { error in
            if let error = error as? NIOExtrasErrors.LeftOverBytesError {
                XCTAssertEqual(
                    Int(dataLength) - 2,  // we're 2 bytes short of the required 7
                    error.leftOverBytes.readableBytes
                )
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testRemoveHandlerWhenBufferIsEmpty() throws {

        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .eight,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let dataLength: Int64 = 5

        var buffer = self.channel.allocator.buffer(capacity: 13)  // 8 byte header + 5 character string
        buffer.writeInteger(dataLength, endianness: .little, as: Int64.self)
        buffer.writeString(standardDataString)

        XCTAssertTrue(try self.channel.writeInbound(buffer).isFull)

        let removeFuture = self.channel.pipeline.syncOperations.removeHandler(self.decoderUnderTest)
        (channel.eventLoop as! EmbeddedEventLoop).run()
        XCTAssertNoThrow(try removeFuture.wait())

        XCTAssertNoThrow(
            XCTAssertEqual(
                standardDataString,
                try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                    String(decoding: $0, as: Unicode.UTF8.self)
                }
            )
        )
        XCTAssertNoThrow(try self.channel.throwIfErrorCaught())
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testRemoveHandlerWhenBufferIsNotEmpty() throws {

        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .eight,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let extraUnusedDataString = "fghi"
        let dataLength: Int64 = 5

        var buffer = self.channel.allocator.buffer(capacity: 17)  // 8 byte header + 5 character string + 4 unused
        buffer.writeInteger(dataLength, endianness: .little, as: Int64.self)
        buffer.writeString(standardDataString + extraUnusedDataString)

        XCTAssertTrue(try channel.writeInbound(buffer).isFull)

        let removeFuture = self.channel.pipeline.syncOperations.removeHandler(self.decoderUnderTest)
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

        XCTAssertNoThrow(
            XCTAssertEqual(
                standardDataString,
                try (self.channel.readInbound(as: ByteBuffer.self)?.readableBytesView).map {
                    String(decoding: $0, as: Unicode.UTF8.self)
                }
            )
        )
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testCloseInChannelRead() {
        let channel = EmbeddedChannel(
            handler: ByteToMessageHandler(LengthFieldBasedFrameDecoder(lengthFieldLength: .four))
        )
        class CloseInReadHandler: ChannelInboundHandler {
            typealias InboundIn = ByteBuffer

            private var numberOfReads = 0

            func channelRead(context: ChannelHandlerContext, data: NIOAny) {
                self.numberOfReads += 1
                XCTAssertEqual(1, self.numberOfReads)
                XCTAssertEqual([UInt8(100)], Array(self.unwrapInboundIn(data).readableBytesView))
                context.close().whenFailure { error in
                    XCTFail("unexpected error: \(error)")
                }
                context.fireChannelRead(data)
            }
        }
        XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(CloseInReadHandler()))

        var buf = channel.allocator.buffer(capacity: 1024)
        buf.writeBytes([UInt8(0), 0, 0, 1, 100])
        XCTAssertNoThrow(try channel.writeInbound(buf))
        XCTAssertNoThrow(XCTAssertEqual([100], Array((try channel.readInbound() as ByteBuffer?)!.readableBytesView)))
        XCTAssertNoThrow(XCTAssertNil(try channel.readInbound()))
    }

    func testBasicVerification() {
        let inputs: [(NIOLengthFieldBitLength, [(Int, String)])] = [
            (
                .oneByte,
                [
                    (6, "abcdef"),
                    (0, ""),
                    (9, "123456789"),
                    (
                        Int(UInt8.max),
                        String(
                            decoding: Array(repeating: UInt8(ascii: "X"), count: Int(UInt8.max)),
                            as: Unicode.UTF8.self
                        )
                    ),
                ]
            ),
            (
                .twoBytes,
                [
                    (1, "a"),
                    (0, ""),
                    (9, "123456789"),
                    (
                        307,
                        String(decoding: Array(repeating: UInt8(ascii: "X"), count: 307), as: Unicode.UTF8.self)
                    ),
                ]
            ),
            (
                .threeBytes,
                [
                    (1, "a"),
                    (0, ""),
                    (9, "123456789"),
                    (
                        307,
                        String(decoding: Array(repeating: UInt8(ascii: "X"), count: 307), as: Unicode.UTF8.self)
                    ),
                ]
            ),
            (
                .fourBytes,
                [
                    (1, "a"),
                    (0, ""),
                    (3, "333"),
                    (
                        307,
                        String(decoding: Array(repeating: UInt8(ascii: "X"), count: 307), as: Unicode.UTF8.self)
                    ),
                ]
            ),
            (
                .eightBytes,
                [
                    (1, "a"),
                    (0, ""),
                    (4, "aaaa"),
                    (
                        307,
                        String(decoding: Array(repeating: UInt8(ascii: "X"), count: 307), as: Unicode.UTF8.self)
                    ),
                ]
            ),
        ]

        for input in inputs {
            let (lenBytes, inputData) = input

            func byteBuffer(length: Int, string: String) -> ByteBuffer {
                var buf = self.channel.allocator.buffer(capacity: string.utf8.count + 8)
                buf.writeInteger(length)
                buf.moveReaderIndex(forwardBy: 8 - lenBytes.length)
                buf.writeString(string)
                return buf
            }

            let inputOutputPairs = inputData.map { (input: (Int, String)) -> (ByteBuffer, [ByteBuffer]) in
                let bytes = byteBuffer(length: input.0, string: input.1)
                return (bytes, [bytes.getSlice(at: bytes.readerIndex + lenBytes.length, length: input.0)!])
            }
            XCTAssertNoThrow(
                try ByteToMessageDecoderVerifier.verifyDecoder(inputOutputPairs: inputOutputPairs) {
                    LengthFieldBasedFrameDecoder(lengthFieldBitLength: lenBytes)
                }
            )
        }
    }
    func testMaximumAllowedLengthWith32BitFieldLength() throws {
        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .four,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let dataLength = UInt32(Int32.max)

        var buffer = self.channel.allocator.buffer(capacity: 4)  // 4 byte header
        buffer.writeInteger(dataLength, endianness: .little, as: UInt32.self)
        buffer.writeString(standardDataString)

        XCTAssertNoThrow(try self.channel.writeInbound(buffer))
    }

    func testMaliciousLengthWith32BitFieldLength() throws {
        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .four,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let dataLength = UInt32(Int32.max) + 1

        var buffer = self.channel.allocator.buffer(capacity: 4)  // 4 byte header
        buffer.writeInteger(dataLength, endianness: .little, as: UInt32.self)
        buffer.writeString(standardDataString)

        XCTAssertThrowsError(try self.channel.writeInbound(buffer))
    }

    func testMaximumAllowedLengthWith64BitFieldLength() throws {
        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .eight,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let dataLength = UInt64(Int32.max)

        var buffer = self.channel.allocator.buffer(capacity: 8)  // 8 byte header
        buffer.writeInteger(dataLength, endianness: .little, as: UInt64.self)
        buffer.writeString(standardDataString)

        XCTAssertNoThrow(try self.channel.writeInbound(buffer))
    }

    func testMaliciousLengthWith64BitFieldLength() {
        self.decoderUnderTest = .init(
            LengthFieldBasedFrameDecoder(
                lengthFieldLength: .eight,
                lengthFieldEndianness: .little
            )
        )
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.decoderUnderTest))

        let dataLength = UInt64(Int32.max) + 1

        var buffer = self.channel.allocator.buffer(capacity: 8)  // 8 byte header
        buffer.writeInteger(dataLength, endianness: .little, as: UInt64.self)

        XCTAssertThrowsError(try self.channel.writeInbound(buffer))
    }
}
