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

// MARK: NIOPCAPRingBuffer
/// Storage for the most recent set of packets captured subject to constraints.
/// Use `addFragment` as the sink to a `NIOWritePCAPHandler` and call `emitPCAP`
/// when you wish to get the recorded data.
/// - Warning:  This class is not thread safe so should only be called from one thread.
public class NIOPCAPRingBuffer {
    private var pcapFragments: CircularBuffer<ByteBuffer>
    private var pcapCurrentBytes: size_t
    private let maximumFragments: Int
    private let maximumBytes: size_t

    /// Initialise the buffer, setting constraints.
    /// - Parameters:
    ///    - maximumFragments: The maximum number of pcap fragments to store.
    ///    - maximumBytes:  The maximum number of bytes to store - note, data written may exceed this by the header size.
    public init(maximumFragments: Int, maximumBytes: Int) {
        precondition(maximumFragments > 0)
        precondition(maximumBytes > 0)
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
        assert(self.pcapFragments.count <= self.maximumFragments)
    }

    /// Record a fragment into the buffer, making space if required.
    /// - Parameters:
    /// - buffer: ByteBuffer containing a pcap fragment to store.
    public func addFragment(_ buffer: ByteBuffer) {
        // Make sure we don't go over on the number of fragments.
        if self.pcapFragments.count >= self.maximumFragments {
            self.popFirst()
        }
        precondition(self.pcapFragments.count < self.maximumFragments)
        
        // Add the new fragment
        self.append(buffer)

        // Trim if we've exceeded byte limit - this could remove multiple, and indeed all fragments.
        while self.pcapCurrentBytes > self.maximumBytes {
            self.popFirst()
        }
        precondition(self.pcapCurrentBytes <= self.maximumBytes)
    }

    /// Emit the captured data to a consuming function; then clear the captured data.
    /// - Parameters:
    /// - consumer: Function which will take the stored fragments and output.
    public func emitPCAP(_ consumer: (CircularBuffer<ByteBuffer>) -> Void) {
        consumer(self.pcapFragments)
        self.pcapFragments.removeAll(keepingCapacity: true)
        self.pcapCurrentBytes = 0

     /*   var buffer = allocator.buffer(capacity: self.pcapCurrentBytes)
        while var next = self.popFirst() {
            buffer.writeBuffer(&next)
        }
        return buffer*/
    }
}
