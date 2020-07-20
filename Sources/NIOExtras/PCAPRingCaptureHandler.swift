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

import NIO

/// Storage for the most recent set of packets captured subject to constraints.
class PCAPRingBuffer {
    private var pcapFragments: CircularBuffer<ByteBuffer>
    private var pcapCurrentBytes: size_t
    private let maximumFragments: UInt
    private let maximumBytes: size_t

    /// Initialise the buffer, setting constraints.
    /// Parameters:
    ///    - maximumFragments: The maximum number of pcap fragments to store.
    ///    - maximumBytes:  The maximum number of bytes to store - note, data written may exceed this by the header size.
    public init(maximumFragments: UInt, maximumBytes: size_t) {
        self.maximumFragments = maximumFragments
        self.maximumBytes = maximumBytes
        self.pcapCurrentBytes = 0
        self.pcapFragments = CircularBuffer(initialCapacity: .init(maximumFragments))
    }
    
    @discardableResult
    private func popFirst() -> ByteBuffer? {
        let popped = self.pcapFragments.popFirst()
        if let popped = popped {
            self.pcapCurrentBytes -= popped.readableBytes
        }
        return popped
    }
    
    private func append(_ buffer: ByteBuffer) {
        self.pcapFragments.append(buffer)
        self.pcapCurrentBytes += buffer.readableBytes
    }

    /// Record a fragment into the buffer, making space if required.
    /// Parameters:
    /// - buffer: ByteBuffer containing a pcap fragment to store.
    func addFragment(_ buffer: ByteBuffer) {
        // Make sure we don't go over on the number of fragments.
        if self.pcapFragments.count >= self.maximumFragments {
            self.popFirst()
        }
        assert(self.pcapFragments.count < self.maximumFragments)
        
        // Add the new fragment
        self.append(buffer)
        
        // Trim if we've exceeded byte limit - this could remove multiple, and indeed all fragments.
        while self.pcapCurrentBytes > self.maximumBytes {
            self.popFirst()
        }
    }

    /// Emit the captured data to a byteBuffer - this drains the captured data.
    /// Parameters:
    /// - allocator: Allocator for creating byte buffers which are stored in the ring buffer.
    func emitPCAP(allocator: ByteBufferAllocator) -> ByteBuffer {
        var buffer = allocator.buffer(capacity: self.pcapCurrentBytes)
        while var next = self.popFirst() {
            buffer.writeBuffer(&next)
        }
        return buffer
    }
}

/// Handler derived from `NIOWritePCAPHandler` to  capture a set of packets prior to an user triggered event.
/// Send `PCAPRingCaptureHandler.RecordPreviousPackets` through as either an InboundEvent or OutboudEvent as
/// appropriate to trigger recording through the `sink` initialisation parameter.
public class NIOPCAPRingCaptureHandler: NIOWritePCAPHandler {
    public typealias InboundIn = Any // Don't care, not looking
    public typealias OutboundIn = Any // Don't care, not looking

    private var pcapBuffer: PCAPRingBuffer
    private let sink: (NIO.ByteBuffer) -> Void

    /// Initialise.
    /// Parameters:
    /// - maximumFragments: Maximum number of fragments to record in any capture.
    /// - maximumBytes: Maximum number of bytes to record in any capture.
    /// - sink: Where to send captured data to.
    public init(maximumFragments: UInt, maximumBytes: size_t, sink: @escaping (NIO.ByteBuffer) -> Void) {
        self.pcapBuffer = PCAPRingBuffer(maximumFragments: maximumFragments, maximumBytes: maximumBytes)
        let ringBuffer = self.pcapBuffer
        self.sink = sink
        super.init(mode: .server,
                   settings: Settings(),
                   fileSink: { bb in ringBuffer.addFragment(bb) })
    }

    /// Triggers writing captured data to the sink if `RecordPreviousPackets` is seen.
    public override func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event as? RecordPreviousPackets != nil {
            recordPCAP(allocator: context.channel.allocator)
        } else {
            super.userInboundEventTriggered(context: context, event: event)
        }
    }

    /// Triggers writing captured data to the sink if `RecordPreviousPackets` is seen.
    public override func triggerUserOutboundEvent(context: ChannelHandlerContext, event: Any, promise: EventLoopPromise<Void>?) {
        if event as? RecordPreviousPackets != nil {
            recordPCAP(allocator: context.channel.allocator)
            promise?.succeed(())
        } else {
            super.triggerUserOutboundEvent(context: context, event: event, promise: promise)
        }
    }

    private func recordPCAP(allocator: ByteBufferAllocator) {
        // Grab the data - and send it to the sink.
        let capturedData = self.pcapBuffer.emitPCAP(allocator: allocator)
        sink(capturedData)
    }
}

extension NIOPCAPRingCaptureHandler {
    public struct RecordPreviousPackets {
        public init() { }
    }
}
