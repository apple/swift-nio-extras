//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftNIO project authors
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
    private func dataForTests() -> [ByteBuffer] {
        return [
            ByteBuffer(repeating: 100, count: 100),
            ByteBuffer(repeating: 50, count: 50),
            ByteBuffer(repeating: 150, count: 150),
            ByteBuffer(repeating: 25, count: 25),
            ByteBuffer(repeating: 75, count: 75),
            ByteBuffer(repeating: 120, count: 120),
        ]
    }
    
    func testNotLimited() {
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: 1000, maximumBytes: 1000000)
        var totalBytes = 0
        for fragment in dataForTests() {
            ringBuffer.addFragment(fragment)
            totalBytes += fragment.readableBytes
        }
        let emitted = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        XCTAssertEqual(emitted.readableBytes, totalBytes)
    }
    
    func testFragmentLimit() {
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: 3, maximumBytes: 1000000)
        for fragment in dataForTests() {
            ringBuffer.addFragment(fragment)
        }
        let emitted = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        XCTAssertEqual(emitted.readableBytes, 25 + 75 + 120)
    }
    
    func testByteLimit() {
        let expectedData = 150 + 25 + 75 + 120
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: 1000, maximumBytes: expectedData + 10)
        for fragment in dataForTests() {
            ringBuffer.addFragment(fragment)
        }
        let emitted = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        XCTAssertEqual(emitted.readableBytes, expectedData)
    }
    
    func testExtremeByteLimit() {
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: 1000, maximumBytes: 10)
        for fragment in dataForTests() {
            ringBuffer.addFragment(fragment)
        }
        let emitted = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        XCTAssertEqual(emitted.readableBytes, 0)
    }
    
    func testUnusedBuffer() {
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: 1000, maximumBytes: 1000)
        let emitted = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        XCTAssertEqual(emitted.readableBytes, 0)
    }
    
    func testDoubleEmitZero() {
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: 1000, maximumBytes: 1000000)
        for fragment in dataForTests() {
            ringBuffer.addFragment(fragment)
        }
        _ = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        let emitted2 = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        XCTAssertEqual(emitted2.readableBytes, 0)
    }
    
    func testDoubleEmitSome() {
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: 1000, maximumBytes: 1000000)
        for fragment in dataForTests() {
            ringBuffer.addFragment(fragment)
        }
        _ = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        
        ringBuffer.addFragment(ByteBuffer(repeating: 75, count: 75))
        let emitted2 = ringBuffer.emitPCAP(allocator: ByteBufferAllocator())
        XCTAssertEqual(emitted2.readableBytes, 75)
    }
    
    func testAsHandlerSink() {
        let fragmentsToRecord = 4
        let channel = EmbeddedChannel()
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: .init(fragmentsToRecord), maximumBytes: 1_000_000)
        XCTAssertNoThrow(try channel.pipeline.addHandler(
                            NIOWritePCAPHandler(mode: .client,
                                                fakeLocalAddress: nil,
                                                fakeRemoteAddress: nil,
                                                fileSink: { ringBuffer.addFragment($0) })).wait())
        channel.localAddress = try! SocketAddress(ipAddress: "255.255.255.254", port: Int(UInt16.max) - 1)
        XCTAssertNoThrow(try channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5678)).wait())
        for data in dataForTests() {
            XCTAssertNoThrow(try channel.writeAndFlush(data).wait())
        }
        XCTAssertNoThrow(try channel.throwIfErrorCaught())
        
        XCTAssertNoThrow(try {
            // See what we've got - hopefully 5 data packets.
            var capturedData = ringBuffer.emitPCAP(allocator: channel.allocator)
            let data = dataForTests()
            for expectedData in data[(data.count - fragmentsToRecord)...] {
                var packet = capturedData.readPCAPRecord()
                let tcpPayloadBytes = try packet?.payload.readTCPIPv4()?.tcpPayload.readableBytes
                XCTAssertEqual(tcpPayloadBytes, expectedData.readableBytes)
            }
        }())
    }

    class TriggerOnCumulativeSizeHandler : ChannelOutboundHandler {
        typealias OutboundIn = ByteBuffer

        private var bytesUntilTrigger: Int
        private var pcapRingBuffer: NIOPCAPRingBuffer
        private var sink: (ByteBuffer) -> ()

        init(triggerBytes: Int, pcapRingBuffer: NIOPCAPRingBuffer, sink: @escaping (ByteBuffer) -> ()) {
            self.bytesUntilTrigger = triggerBytes
            self.pcapRingBuffer = pcapRingBuffer
            self.sink = sink
        }

        func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
            if bytesUntilTrigger > 0 {
                self.bytesUntilTrigger -= self.unwrapOutboundIn(data).readableBytes
                if self.bytesUntilTrigger <= 0 {
                    let ourPromise = context.eventLoop.makePromise(of: Void.self)
                    context.write(data, promise: ourPromise)
                    ourPromise.futureResult.flatMap {
                        self.sink(self.pcapRingBuffer.emitPCAP(allocator: context.channel.allocator))
                        return ourPromise.futureResult
                    }.cascade(to: promise)
                    return
                }
            }
            context.write(data, promise: promise)
        }
    }

    func testHandler() {
        let maximumFragments = 3
        let triggerEndIndex = 5
        var testTriggered = false

        func testRecordedBytes(buffer: ByteBuffer) {
            var capturedData = buffer
            XCTAssertNoThrow(try {
                testTriggered = true
                // See what we've got.
                let data = dataForTests()
                for expectedData in data[(triggerEndIndex - maximumFragments)..<triggerEndIndex] {
                    var packet = capturedData.readPCAPRecord()
                    let tcpPayloadBytes = try packet?.payload.readTCPIPv4()?.tcpPayload.readableBytes
                    XCTAssertEqual(tcpPayloadBytes, expectedData.readableBytes)
                }
            }())
        }


        let channel = EmbeddedChannel()
        let trigger = self.dataForTests()[0..<triggerEndIndex]
            .compactMap { t in t.readableBytes }.reduce(0, +)

        let pcapRingBuffer = NIOPCAPRingBuffer(maximumFragments: .init(maximumFragments),
                                               maximumBytes: 1_000_000)
        XCTAssertNoThrow(try channel.pipeline.addHandler(
                            NIOWritePCAPHandler(mode: .client,
                                                fileSink: pcapRingBuffer.addFragment),
                name: "capture").flatMap {
                    return channel.pipeline.addHandler(
                        TriggerOnCumulativeSizeHandler(triggerBytes: trigger,
                                                       pcapRingBuffer: pcapRingBuffer,
                                                       sink: testRecordedBytes),
                        name: "trigger")
                }.wait())

        channel.localAddress = try! SocketAddress(ipAddress: "255.255.255.254", port: Int(UInt16.max) - 1)
        XCTAssertNoThrow(try channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5678)).wait())
        for data in dataForTests() {
            XCTAssertNoThrow(try channel.writeAndFlush(data).wait())
        }
        XCTAssertNoThrow(try channel.throwIfErrorCaught())
        XCTAssert(testTriggered)    // Just to make sure something actually happened.
    }
}
