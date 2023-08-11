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

import NIOConcurrencyHelpers
import NIOCore

// MARK: NIOPCAPRingBuffer
/// Storage for the most recent set of packets captured subject to constraints.
/// Use ``addFragment(_:)`` as the sink to a ``NIOWritePCAPHandler`` and call ``emitPCAP()``
/// when you wish to get the recorded data.
/// - Note: This class is annotated `@unchecked Sendable` because its mutable state is protected by a lock.
public final class NIOPCAPRingBuffer: @unchecked Sendable {
    private let maximumFragments: Int
    private let maximumBytes: Int
    
    private let pcapLock = NIOLock()
    private var pcapFragments: CircularBuffer<ByteBuffer>
    private var pcapCurrentBytes: Int

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
        self.pcapFragments = CircularBuffer(initialCapacity: maximumFragments)
    }

    /// Initialise the buffer, setting constraints
    /// - Parameter maximumBytes: The maximum number of bytes to store - note, data written may exceed this by the header size.
    public convenience init(maximumBytes: Int) {
        self.init(maximumFragments: .max, maximumBytes: maximumBytes)
    }

    /// Initialise the buffer, setting constraints
    /// - Parameter maximumFragments: The maximum number of pcap fragments to store.
    public convenience init(maximumFragments: Int) {
        self.init(maximumFragments: maximumFragments, maximumBytes: .max)
    }
    
    @discardableResult
    private func popFirst() -> ByteBuffer? {
        self.pcapLock.withLock {
            let popped = self.pcapFragments.popFirst()
            if let popped = popped {
                self.pcapCurrentBytes -= popped.readableBytes
            }
            return popped
        }
    }
    
    private func append(_ buffer: ByteBuffer) {
        self.pcapLock.withLock {
            self.pcapFragments.append(buffer)
            self.pcapCurrentBytes += buffer.readableBytes
            assert(self.pcapFragments.count <= self.maximumFragments)
            // It's expected that the caller will have made room if required
            // for the fragment but we may well go over on bytes - they're
            // expected to fix that afterwards.
        }
    }

    /// Record a fragment into the buffer, making space if required.
    /// - Parameter buffer: ByteBuffer containing a pcap fragment to store
    public func addFragment(_ buffer: ByteBuffer) {
        // Make sure we don't go over on the number of fragments.
        if self.pcapLock.withLock({ self.pcapFragments.count }) >= self.maximumFragments {
            self.popFirst()
        }
        precondition(self.pcapLock.withLock({ self.pcapFragments.count }) < self.maximumFragments)

        // Add the new fragment
        self.append(buffer)

        // Trim if we've exceeded byte limit - this could remove multiple, and indeed all fragments.
        while self.pcapLock.withLock({ self.pcapCurrentBytes }) > self.maximumBytes {
            self.popFirst()
        }
        precondition(self.pcapLock.withLock({ self.pcapCurrentBytes }) <= self.maximumBytes)
    }

    /// Emit the captured data to a consuming function; then clear the captured data.
    /// - Returns: A ciruclar buffer of captured fragments.
    public func emitPCAP() -> CircularBuffer<ByteBuffer> {
        self.pcapLock.withLock {
            let toReturn = self.pcapFragments // Copy before clearing.
            self.pcapFragments.removeAll(keepingCapacity: true)
            self.pcapCurrentBytes = 0
            return toReturn
        }
    }
}
