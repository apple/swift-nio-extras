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

import CNIOExtrasZlib
import NIO

public enum NIOHTTPCompressionSettings {

    public struct CompressionAlgorithm: CustomStringConvertible {
        enum Algorithm: String {
            case gzip
            case deflate
        }
        let algorithm: Algorithm
        
        /// return as String
        public var description: String { return algorithm.rawValue }
        
        public static let gzip = CompressionAlgorithm(algorithm: .gzip)
        public static let deflate = CompressionAlgorithm(algorithm: .deflate)
    }
        
    public struct CompressionError: Error, CustomStringConvertible, Equatable {
        enum ErrorType: String {
            case uncompressedWritesPending
            case noDataToWrite
        }
        let error: ErrorType
        
        /// return as String
        public var description: String { return error.rawValue }
        
        public static let uncompressedWritesPending = CompressionError(error: .uncompressedWritesPending)
        public static let noDataToWrite = CompressionError(error: .noDataToWrite)
    }
        
    struct Compressor {
        private var stream = z_stream()
        var isActive = false

        init() { }

        /// Set up the encoder for compressing data according to a specific
        /// algorithm.
        mutating func initialize(encoding: CompressionAlgorithm) {
            assert(!isActive)
            isActive = true
            // zlib docs say: The application must initialize zalloc, zfree and opaque before calling the init function.
            stream.zalloc = nil
            stream.zfree = nil
            stream.opaque = nil

            let windowBits: Int32
            switch encoding.algorithm {
            case .deflate:
                windowBits = 15
            case .gzip:
                windowBits = 16 + 15
            }

            let rc = CNIOExtrasZlib_deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, windowBits, 8, Z_DEFAULT_STRATEGY)
            precondition(rc == Z_OK, "Unexpected return from zlib init: \(rc)")
        }

        mutating func compress(inputBuffer: inout ByteBuffer, allocator: ByteBufferAllocator, finalise: Bool) -> ByteBuffer {
            assert(isActive)
            let flags = finalise ? Z_FINISH : Z_SYNC_FLUSH
            guard inputBuffer.readableBytes > 0 || finalise == true else { return allocator.buffer(capacity: 0) }
            // deflateBound() provides an upper limit on the number of bytes the input can
            // compress to. We add 5 bytes to handle the fact that Z_SYNC_FLUSH will append
            // an empty stored block that is 5 bytes long.
            let bufferSize = Int(deflateBound(&stream, UInt(inputBuffer.readableBytes)))
            var outputBuffer = allocator.buffer(capacity: bufferSize)
            stream.oneShotDeflate(from: &inputBuffer, to: &outputBuffer, flag: flags)
            return outputBuffer
        }
        
        mutating func shutdown() {
            assert(isActive)
            isActive = false
            deflateEnd(&stream)
        }
        
        mutating func shutdownIfActive() {
            if isActive {
                isActive = false
                deflateEnd(&stream)
            }
        }
    }
}

extension z_stream {
    /// Executes deflate from one buffer to another buffer. The advantage of this method is that it
    /// will ensure that the stream is "safe" after each call (that is, that the stream does not have
    /// pointers to byte buffers any longer).
    mutating func oneShotDeflate(from: inout ByteBuffer, to: inout ByteBuffer, flag: Int32) {
        defer {
            self.avail_in = 0
            self.next_in = nil
            self.avail_out = 0
            self.next_out = nil
        }

        from.readWithUnsafeMutableReadableBytes { dataPtr in
            let typedPtr = dataPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let typedDataPtr = UnsafeMutableBufferPointer(start: typedPtr,
                                                          count: dataPtr.count)

            self.avail_in = UInt32(typedDataPtr.count)
            self.next_in = typedDataPtr.baseAddress!

            let rc = deflateToBuffer(buffer: &to, flag: flag)
            precondition(rc == Z_OK || rc == Z_STREAM_END, "One-shot compression failed: \(rc)")

            return typedDataPtr.count - Int(self.avail_in)
        }
    }

    /// A private function that sets the deflate target buffer and then calls deflate.
    /// This relies on having the input set by the previous caller: it will use whatever input was
    /// configured.
    private mutating func deflateToBuffer(buffer: inout ByteBuffer, flag: Int32) -> Int32 {
        var rc = Z_OK

        buffer.writeWithUnsafeMutableBytes(minimumWritableBytes: buffer.capacity) { outputPtr in
            let typedOutputPtr = UnsafeMutableBufferPointer(start: outputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                                                            count: outputPtr.count)
            self.avail_out = UInt32(typedOutputPtr.count)
            self.next_out = typedOutputPtr.baseAddress!
            rc = deflate(&self, flag)
            return typedOutputPtr.count - Int(self.avail_out)
        }

        return rc
    }
}
