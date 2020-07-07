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
internal struct PCAPRingBuffer {
    private var pcapFragments: CircularBuffer<ByteBuffer>
    private var pcapCurrentBytes: size_t
    private let maximumFragments: UInt
    private let maximumBytes: size_t

    /// Initialise the buffer, setting constraints.
    /// Parameters:
    ///    - maximumFragments: The maximum number of pcap fragments to store.
    ///    - maximumBytes:  The maximum number of bytes to store - note, data written may exceed this by the header size.
    init(maximumFragments: UInt, maximumBytes: size_t) {
        self.maximumFragments = maximumFragments
        self.maximumBytes = maximumBytes
        self.pcapCurrentBytes = 0
        self.pcapFragments = CircularBuffer(initialCapacity: .init(maximumFragments))
    }
    
    @discardableResult
    private mutating func popFirst() -> ByteBuffer? {
        let popped = self.pcapFragments.popFirst()
        if let popped = popped {
            self.pcapCurrentBytes -= popped.readableBytes
        }
        return popped
    }
    
    private mutating func append(_ buffer: ByteBuffer) {
        self.pcapFragments.append(buffer)
        self.pcapCurrentBytes += buffer.readableBytes
    }

    /// Record a fragment into the buffer, making space if required.
    mutating func addFragment(_ buffer: ByteBuffer) {
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
    mutating func emitPCAP(allocator: ByteBufferAllocator) -> ByteBuffer {
        var buffer = allocator.buffer(capacity: self.pcapCurrentBytes)
        while var next = self.popFirst() {
            buffer.writeBuffer(&next)
        }
        return buffer
    }
}
