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
import XCTest

@testable import NIOExtras

private let standardDataString = "abcde"
private let standardDataStringCount = standardDataString.utf8.count

class LengthFieldPrependerTest: XCTestCase {
    private var channel: EmbeddedChannel!
    private var encoderUnderTest: LengthFieldPrepender!

    override func setUp() {
        self.channel = EmbeddedChannel()
    }
    func testWrite3BytesOfUInt32Write() {
        var buffer = ByteBuffer()
        buffer.write24UInt(5, endianness: .little)
        XCTAssertEqual(Array(buffer.readableBytesView), [5, 0, 0])
        XCTAssertEqual(buffer.read24UInt(endianness: .little), 5)

        buffer.write24UInt(5, endianness: .big)
        XCTAssertEqual(Array(buffer.readableBytesView), [0, 0, 5])
        XCTAssertEqual(buffer.read24UInt(endianness: .big), 5)
    }
    func testEncodeWithUInt8HeaderWithData() throws {

        self.encoderUnderTest = LengthFieldPrepender(
            lengthFieldLength: .one,
            lengthFieldEndianness: .little
        )

        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.encoderUnderTest))

        let dataBytes: [UInt8] = [10, 20, 30, 40]

        var buffer = self.channel.allocator.buffer(capacity: dataBytes.count)
        buffer.writeBytes(dataBytes)

        XCTAssertNoThrow(try self.channel.writeAndFlush(buffer).wait())

        if case .some(.byteBuffer(var headerBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let outputData = headerBuffer.readBytes(length: headerBuffer.readableBytes)
            XCTAssertEqual([UInt8(dataBytes.count)], outputData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let outputData = outputBuffer.readBytes(length: outputBuffer.readableBytes)
            XCTAssertEqual(dataBytes, outputData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        XCTAssertNoThrow(XCTAssertNil(try self.channel.readOutbound()))
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testEncodeWithUInt16HeaderWithString() throws {

        let endianness: Endianness = .little

        self.encoderUnderTest = LengthFieldPrepender(
            lengthFieldLength: .two,
            lengthFieldEndianness: endianness
        )

        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.encoderUnderTest))

        var buffer = self.channel.allocator.buffer(capacity: standardDataStringCount)
        buffer.writeString(standardDataString)

        XCTAssertNoThrow(try self.channel.writeAndFlush(buffer).wait())

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt16.self).map({ Int($0) })
            XCTAssertEqual(standardDataStringCount, sizeInHeader)

            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let bodyString = outputBuffer.readString(length: standardDataStringCount)
            XCTAssertEqual(standardDataString, bodyString)

            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        XCTAssertNoThrow(XCTAssertNil(try self.channel.readOutbound()))
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testEncodeWithUInt24HeaderWithString() throws {

        let endianness: Endianness = .little

        self.encoderUnderTest = LengthFieldPrepender(
            lengthFieldBitLength: .threeBytes,
            lengthFieldEndianness: endianness
        )

        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.encoderUnderTest))

        var buffer = self.channel.allocator.buffer(capacity: standardDataStringCount)
        buffer.writeString(standardDataString)

        XCTAssertNoThrow(try self.channel.writeAndFlush(buffer).wait())

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let sizeInHeader = outputBuffer.read24UInt(endianness: endianness).map({ Int($0) })
            XCTAssertEqual(standardDataStringCount, sizeInHeader)

            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let bodyString = outputBuffer.readString(length: standardDataStringCount)
            XCTAssertEqual(standardDataString, bodyString)

            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        XCTAssertNoThrow(XCTAssertNil(try self.channel.readOutbound()))
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testEncodeWithUInt32HeaderWithString() throws {

        let endianness: Endianness = .little

        self.encoderUnderTest = LengthFieldPrepender(
            lengthFieldLength: .four,
            lengthFieldEndianness: endianness
        )

        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.encoderUnderTest))

        var buffer = self.channel.allocator.buffer(capacity: standardDataStringCount)
        buffer.writeString(standardDataString)

        XCTAssertNoThrow(try self.channel.writeAndFlush(buffer).wait())

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt32.self).map({ Int($0) })
            XCTAssertEqual(standardDataStringCount, sizeInHeader)

            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let bodyString = outputBuffer.readString(length: standardDataStringCount)
            XCTAssertEqual(standardDataString, bodyString)

            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        XCTAssertNoThrow(XCTAssertNil(try self.channel.readOutbound()))
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testEncodeWithUInt64HeaderWithString() throws {

        let endianness: Endianness = .little

        self.encoderUnderTest = LengthFieldPrepender(
            lengthFieldLength: .eight,
            lengthFieldEndianness: endianness
        )

        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.encoderUnderTest))

        var buffer = self.channel.allocator.buffer(capacity: standardDataStringCount)
        buffer.writeString(standardDataString)

        XCTAssertNoThrow(try self.channel.writeAndFlush(buffer).wait())

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt64.self).map({ Int($0) })
            XCTAssertEqual(standardDataStringCount, sizeInHeader)

            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let bodyString = outputBuffer.readString(length: outputBuffer.readableBytes)
            XCTAssertEqual(standardDataString, bodyString)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        XCTAssertNoThrow(XCTAssertNil(try self.channel.readOutbound()))
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testEncodeWithInt64HeaderWithString() throws {

        let endianness: Endianness = .little

        self.encoderUnderTest = LengthFieldPrepender(
            lengthFieldLength: .eight,
            lengthFieldEndianness: endianness
        )

        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.encoderUnderTest))

        var buffer = self.channel.allocator.buffer(capacity: standardDataStringCount)
        buffer.writeString(standardDataString)

        XCTAssertNoThrow(try self.channel.writeAndFlush(buffer).wait())

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: Int64.self).map({ Int($0) })
            XCTAssertEqual(standardDataStringCount, sizeInHeader)

            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let bodyString = outputBuffer.readString(length: standardDataStringCount)
            XCTAssertEqual(standardDataString, bodyString)

            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        XCTAssertNoThrow(XCTAssertNil(try self.channel.readOutbound()))
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testEncodeWithUInt64HeaderStringBigEndian() throws {

        let endianness: Endianness = .big

        self.encoderUnderTest = LengthFieldPrepender(
            lengthFieldLength: .eight,
            lengthFieldEndianness: endianness
        )

        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.encoderUnderTest))

        var buffer = self.channel.allocator.buffer(capacity: standardDataStringCount)
        buffer.writeString(standardDataString)

        XCTAssertNoThrow(try self.channel.writeAndFlush(buffer).wait())

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt64.self).map({ Int($0) })
            XCTAssertEqual(standardDataStringCount, sizeInHeader)

            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let bodyString = outputBuffer.readString(length: standardDataStringCount)
            XCTAssertEqual(standardDataString, bodyString)

            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        XCTAssertNoThrow(XCTAssertNil(try self.channel.readOutbound()))
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testEncodeWithInt64HeaderStringDefaultingToBigEndian() throws {

        self.encoderUnderTest = LengthFieldPrepender(lengthFieldLength: .eight)

        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.encoderUnderTest))

        var buffer = self.channel.allocator.buffer(capacity: standardDataStringCount)
        buffer.writeString(standardDataString)

        XCTAssertNoThrow(try self.channel.writeAndFlush(buffer).wait())

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let sizeInHeader = outputBuffer.readInteger(endianness: .big, as: UInt64.self).map({ Int($0) })
            XCTAssertEqual(standardDataStringCount, sizeInHeader)

            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let bodyString = outputBuffer.readString(length: standardDataStringCount)
            XCTAssertEqual(standardDataString, bodyString)

            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        XCTAssertNoThrow(XCTAssertNil(try self.channel.readOutbound()))
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testEmptyBuffer() throws {

        let endianness: Endianness = .little

        self.encoderUnderTest = LengthFieldPrepender(
            lengthFieldLength: .eight,
            lengthFieldEndianness: endianness
        )

        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.encoderUnderTest))

        let buffer = self.channel.allocator.buffer(capacity: 0)

        XCTAssertNoThrow(try self.channel.writeAndFlush(buffer).wait())

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt64.self).map({ Int($0) })
            XCTAssertEqual(0, sizeInHeader)

            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        // Check that if there is any more buffer it has a zero size.
        if case .some(.byteBuffer(let outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {
            XCTAssertEqual(0, outputBuffer.readableBytes)
        }

        XCTAssertNoThrow(XCTAssertNil(try self.channel.readOutbound()))
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testLargeBuffer() throws {

        let endianness: Endianness = .little

        self.encoderUnderTest = LengthFieldPrepender(
            lengthFieldLength: .eight,
            lengthFieldEndianness: endianness
        )

        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.encoderUnderTest))

        let contents = [UInt8](repeating: 200, count: 514)

        var buffer = self.channel.allocator.buffer(capacity: contents.count)
        buffer.writeBytes(contents)

        XCTAssertNoThrow(try self.channel.writeAndFlush(buffer).wait())

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let sizeInHeader = outputBuffer.readInteger(endianness: endianness, as: UInt64.self).map({ Int($0) })
            XCTAssertEqual(contents.count, sizeInHeader)

            let additionalData = outputBuffer.readBytes(length: 1)
            XCTAssertNil(additionalData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        if case .some(.byteBuffer(var outputBuffer)) = try self.channel.readOutbound(as: IOData.self) {

            let bodyData = outputBuffer.readBytes(length: outputBuffer.readableBytes)
            XCTAssertEqual(contents, bodyData)

        } else {
            XCTFail("couldn't read ByteBuffer from channel")
        }

        XCTAssertNoThrow(XCTAssertNil(try self.channel.readOutbound()))
        XCTAssertTrue(try self.channel.finish().isClean)
    }

    func testTooLargeForLengthField() throws {

        let endianness: Endianness = .little

        // One byte has maximum integer description of 256
        self.encoderUnderTest = LengthFieldPrepender(
            lengthFieldLength: .one,
            lengthFieldEndianness: endianness
        )

        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(self.encoderUnderTest))

        let contents = [UInt8](repeating: 200, count: 300)

        var buffer = self.channel.allocator.buffer(capacity: contents.count)
        buffer.writeBytes(contents)

        XCTAssertThrowsError(try self.channel.writeAndFlush(buffer).wait()) { error in
            XCTAssertEqual(.messageDataTooLongForLengthField, error as? LengthFieldPrependerError)
        }

        XCTAssertNoThrow(XCTAssertNil(try self.channel.readOutbound()))
        XCTAssertTrue(try self.channel.finish().isClean)
    }
}
