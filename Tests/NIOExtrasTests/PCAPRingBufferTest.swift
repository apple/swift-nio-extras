//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the SwiftNIO project authors
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

class PCAPRingBufferTest: XCTestCase {
    private func dataForTests() -> [ByteBuffer] {
        [
            ByteBuffer(repeating: 100, count: 100),
            ByteBuffer(repeating: 50, count: 50),
            ByteBuffer(repeating: 150, count: 150),
            ByteBuffer(repeating: 25, count: 25),
            ByteBuffer(repeating: 75, count: 75),
            ByteBuffer(repeating: 120, count: 120),
        ]
    }

    private static func captureBytes(ringBuffer: NIOPCAPRingBuffer) -> ByteBuffer {
        func flattenBuffers(capturedPackets: CircularBuffer<ByteBuffer>) -> ByteBuffer {
            var resultBuffer = ByteBuffer()
            for buffer in capturedPackets {
                var buffer = buffer
                resultBuffer.writeBuffer(&buffer)
            }
            return resultBuffer
        }

        let capturedPackets = ringBuffer.emitPCAP()
        return flattenBuffers(capturedPackets: capturedPackets)
    }

    func testNotLimited() {
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: 1000, maximumBytes: 1_000_000)
        var totalBytes = 0
        for fragment in dataForTests() {
            ringBuffer.addFragment(fragment)
            totalBytes += fragment.readableBytes
        }
        let emitted = PCAPRingBufferTest.captureBytes(ringBuffer: ringBuffer)
        XCTAssertEqual(emitted.readableBytes, totalBytes)
    }

    func testFragmentLimit() {
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: 3, maximumBytes: 1_000_000)
        for fragment in dataForTests() {
            ringBuffer.addFragment(fragment)
        }
        let emitted = PCAPRingBufferTest.captureBytes(ringBuffer: ringBuffer)
        XCTAssertEqual(emitted.readableBytes, 25 + 75 + 120)
    }

    func testByteLimit() {
        let expectedData = 150 + 25 + 75 + 120
        let ringBuffer = NIOPCAPRingBuffer(maximumBytes: expectedData + 10)
        for fragment in dataForTests() {
            ringBuffer.addFragment(fragment)
        }
        let emitted = PCAPRingBufferTest.captureBytes(ringBuffer: ringBuffer)
        XCTAssertEqual(emitted.readableBytes, expectedData)
    }

    func testByteOnLimit() {
        let expectedData = 120
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: 1000, maximumBytes: expectedData)
        for fragment in dataForTests() {
            ringBuffer.addFragment(fragment)
        }
        let emitted = PCAPRingBufferTest.captureBytes(ringBuffer: ringBuffer)
        XCTAssertEqual(emitted.readableBytes, expectedData)
    }

    func testExtremeByteLimit() {
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: 1000, maximumBytes: 10)
        for fragment in dataForTests() {
            ringBuffer.addFragment(fragment)
        }
        let emitted = PCAPRingBufferTest.captureBytes(ringBuffer: ringBuffer)
        XCTAssertEqual(emitted.readableBytes, 0)
    }

    func testUnusedBuffer() {
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: 1000, maximumBytes: 1000)
        let emitted = PCAPRingBufferTest.captureBytes(ringBuffer: ringBuffer)
        XCTAssertEqual(emitted.readableBytes, 0)
    }

    func testDoubleEmitZero() {
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: 1000, maximumBytes: 1_000_000)
        for fragment in dataForTests() {
            ringBuffer.addFragment(fragment)
        }
        _ = PCAPRingBufferTest.captureBytes(ringBuffer: ringBuffer)
        let emitted2 = PCAPRingBufferTest.captureBytes(ringBuffer: ringBuffer)
        XCTAssertEqual(emitted2.readableBytes, 0)
    }

    func testDoubleEmitSome() {
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: 1000, maximumBytes: 1_000_000)
        for fragment in dataForTests() {
            ringBuffer.addFragment(fragment)
        }
        _ = PCAPRingBufferTest.captureBytes(ringBuffer: ringBuffer)

        ringBuffer.addFragment(ByteBuffer(repeating: 75, count: 75))
        let emitted2 = PCAPRingBufferTest.captureBytes(ringBuffer: ringBuffer)
        XCTAssertEqual(emitted2.readableBytes, 75)
    }

    func testAsHandlerSink() {
        let fragmentsToRecord = 4
        let channel = EmbeddedChannel()
        let ringBuffer = NIOPCAPRingBuffer(maximumFragments: .init(fragmentsToRecord), maximumBytes: 1_000_000)
        XCTAssertNoThrow(
            try channel.pipeline.syncOperations.addHandler(
                NIOWritePCAPHandler(
                    mode: .client,
                    fakeLocalAddress: nil,
                    fakeRemoteAddress: nil,
                    fileSink: { ringBuffer.addFragment($0) }
                )
            )
        )
        channel.localAddress = try! SocketAddress(ipAddress: "255.255.255.254", port: Int(UInt16.max) - 1)
        XCTAssertNoThrow(try channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5678)).wait())
        for data in dataForTests() {
            XCTAssertNoThrow(try channel.writeAndFlush(data).wait())
        }
        XCTAssertNoThrow(try channel.throwIfErrorCaught())

        XCTAssertNoThrow(
            try {
                // See what we've got - hopefully 5 data packets.
                var capturedData = PCAPRingBufferTest.captureBytes(ringBuffer: ringBuffer)
                let data = dataForTests()
                for expectedData in data[(data.count - fragmentsToRecord)...] {
                    var packet = capturedData.readPCAPRecord()
                    let tcpPayloadBytes = try packet?.payload.readTCPIPv4()?.tcpPayload.readableBytes
                    XCTAssertEqual(tcpPayloadBytes, expectedData.readableBytes)
                }
            }()
        )
    }

    class TriggerOnCumulativeSizeHandler: ChannelOutboundHandler {
        typealias OutboundIn = ByteBuffer

        private var bytesUntilTrigger: Int
        private var pcapRingBuffer: NIOPCAPRingBuffer
        private let sink: (ByteBuffer) -> Void

        init(triggerBytes: Int, pcapRingBuffer: NIOPCAPRingBuffer, sink: @escaping (ByteBuffer) -> Void) {
            self.bytesUntilTrigger = triggerBytes
            self.pcapRingBuffer = pcapRingBuffer
            self.sink = sink
        }

        func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
            if bytesUntilTrigger > 0 {
                self.bytesUntilTrigger -= self.unwrapOutboundIn(data).readableBytes
                if self.bytesUntilTrigger <= 0 {
                    context.write(data).assumeIsolated().map {
                        self.sink(captureBytes(ringBuffer: self.pcapRingBuffer))
                    }.nonisolated().cascade(to: promise)
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
            XCTAssertNoThrow(
                try {
                    testTriggered = true
                    // See what we've got.
                    let data = dataForTests()
                    for expectedData in data[(triggerEndIndex - maximumFragments)..<triggerEndIndex] {
                        var packet = capturedData.readPCAPRecord()
                        let tcpPayloadBytes = try packet?.payload.readTCPIPv4()?.tcpPayload.readableBytes
                        XCTAssertEqual(tcpPayloadBytes, expectedData.readableBytes)
                    }
                }()
            )
        }

        let trigger = self.dataForTests()[0..<triggerEndIndex]
            .compactMap { t in t.readableBytes }.reduce(0, +)

        let pcapRingBuffer = NIOPCAPRingBuffer(
            maximumFragments: .init(maximumFragments),
            maximumBytes: 1_000_000
        )

        let channel = EmbeddedChannel(handlers: [
            NIOWritePCAPHandler(mode: .client, fileSink: pcapRingBuffer.addFragment),
            TriggerOnCumulativeSizeHandler(
                triggerBytes: trigger,
                pcapRingBuffer: pcapRingBuffer,
                sink: testRecordedBytes
            ),
        ])

        channel.localAddress = try! SocketAddress(ipAddress: "255.255.255.254", port: Int(UInt16.max) - 1)
        XCTAssertNoThrow(try channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5678)).wait())
        for data in dataForTests() {
            XCTAssertNoThrow(try channel.writeAndFlush(data).wait())
        }
        XCTAssertNoThrow(try channel.throwIfErrorCaught())
        XCTAssert(testTriggered)  // Just to make sure something actually happened.
    }
}
