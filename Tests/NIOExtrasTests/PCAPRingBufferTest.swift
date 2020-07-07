//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
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
@testable import NIOExtras

class PCAPRingBufferTest: XCTestCase {
    private func testData() -> [ByteBuffer] {
        return [
            ByteBuffer(repeating: 100, count: 100),
            ByteBuffer(repeating: 50, count: 50),
            ByteBuffer(repeating: 150, count: 150),
            ByteBuffer(repeating: 25, count: 25),
            ByteBuffer(repeating: 75, count: 75),
            ByteBuffer(repeating: 120, count: 120),
        ]
    }
    
    func testAddsHeader() {
        var ringBuffer = PCAPRingBuffer(maximumFragments: 1000, maximumBytes: 1000000)
        var totalBytes = 0
        for fragment in testData() {
            ringBuffer.addFragment(fragment)
            totalBytes += fragment.readableBytes
        }
        let emitted = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        XCTAssertEqual(emitted.readableBytes, totalBytes + NIOWritePCAPHandler.pcapFileHeader.readableBytes)
    }
    
    func testNoHeaderDuplication() {
        var ringBuffer = PCAPRingBuffer(maximumFragments: 1000, maximumBytes: 1000000)
        var totalBytes = NIOWritePCAPHandler.pcapFileHeader.readableBytes
        ringBuffer.addFragment(NIOWritePCAPHandler.pcapFileHeader)
        for fragment in testData() {
            ringBuffer.addFragment(fragment)
            totalBytes += fragment.readableBytes
        }
        let emitted = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        XCTAssertEqual(emitted.readableBytes, totalBytes)
    }
    
    func testFragmentLimit() {
        var ringBuffer = PCAPRingBuffer(maximumFragments: 3, maximumBytes: 1000000)
        for fragment in testData() {
            ringBuffer.addFragment(fragment)
        }
        let emitted = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        XCTAssertEqual(emitted.readableBytes, 25 + 75 + 120 + NIOWritePCAPHandler.pcapFileHeader.readableBytes)
    }
    
    func testByteLimit() {
        let expectedData = 150 + 25 + 75 + 120
        var ringBuffer = PCAPRingBuffer(maximumFragments: 1000, maximumBytes: expectedData + 10)
        for fragment in testData() {
            ringBuffer.addFragment(fragment)
        }
        let emitted = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        XCTAssertEqual(emitted.readableBytes, expectedData + NIOWritePCAPHandler.pcapFileHeader.readableBytes)
    }
    
    func testExtremeByteLimit() {
        var ringBuffer = PCAPRingBuffer(maximumFragments: 1000, maximumBytes: 10)
        for fragment in testData() {
            ringBuffer.addFragment(fragment)
        }
        let emitted = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        XCTAssertEqual(emitted.readableBytes, 0)
    }
    
    func testUnusedBuffer() {
        var ringBuffer = PCAPRingBuffer(maximumFragments: 1000, maximumBytes: 1000)
        let emitted = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        XCTAssertEqual(emitted.readableBytes, 0)
    }
    
    func testDoubleEmitZero() {
        var ringBuffer = PCAPRingBuffer(maximumFragments: 1000, maximumBytes: 1000000)
        for fragment in testData() {
            ringBuffer.addFragment(fragment)
        }
        _ = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        let emitted2 = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        XCTAssertEqual(emitted2.readableBytes, 0)
    }
    
    func testDoubleEmitSome() {
        var ringBuffer = PCAPRingBuffer(maximumFragments: 1000, maximumBytes: 1000000)
        for fragment in testData() {
            ringBuffer.addFragment(fragment)
        }
        _ = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        
        ringBuffer.addFragment(ByteBuffer(repeating: 75, count: 75))
        let emitted2 = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        XCTAssertEqual(emitted2.readableBytes, 75 + NIOWritePCAPHandler.pcapFileHeader.readableBytes)
    }
    
    func testInHandler() {
        let channel = EmbeddedChannel()
        var ringBuffer = PCAPRingBuffer(maximumFragments: 5, maximumBytes: 1_000_000)
        XCTAssertNoThrow(try channel.pipeline.addHandler(
                            NIOWritePCAPHandler(mode: .client,
                                                fakeLocalAddress: nil,
                                                fakeRemoteAddress: nil,
                                                fileSink: { ringBuffer.addFragment($0) })).wait())
        channel.localAddress = try! SocketAddress(ipAddress: "255.255.255.254", port: Int(UInt16.max) - 1)
        XCTAssertNoThrow(try channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5678)).wait())
        for data in testData() {
            XCTAssertNoThrow(try channel.writeAndFlush(data).wait())
        }
        XCTAssertNoThrow(try channel.throwIfErrorCaught())
        // See what we've got - hopefully 5 data packets.
        var capturedData = ringBuffer.emitPCAP(allocator: channel.allocator)
        let p1 = capturedData.readPCAPRecord()
        print(p1)
        
        
       /* XCTAssertNoThrow(try {
            var capturedData = try channel.eventLoop.scheduleTask(in: .nanoseconds(0)) {
                return ringBuffer.emitPCAP(allocator: channel.allocator)
            }.futureResult.wait()
            let p1 = capturedData.readPCAPRecord()
            print(p1)
        } ()) */
        
    }
        
}
