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

import CNIOExtrasZlib
import NIO

public enum NIOHTTPDecompression {
    /// Specifies how to limit decompression inflation.
    public struct DecompressionLimit {
        private enum Limit {
            case none
            case size(Int)
            case ratio(Int)
        }

        private var limit: Limit

        /// No limit will be set.
        public static let none = DecompressionLimit(limit: .none)
        /// Limit will be set on the request body size.
        public static func size(_ value: Int) -> DecompressionLimit { return DecompressionLimit(limit: .size(value)) }
        /// Limit will be set on a ratio between compressed body size and decompressed result.
        public static func ratio(_ value: Int) -> DecompressionLimit { return DecompressionLimit(limit: .ratio(value)) }

        func exceeded(compressed: Int, decompressed: Int) -> Bool {
            switch self.limit {
            case .none:
                return false
            case .size(let allowed):
                return compressed > allowed
            case .ratio(let ratio):
                return decompressed > compressed * ratio
            }
        }
    }

    public enum DecompressionError: Error {
        case limit
        case inflationError(Int)
        case initializationError(Int)
    }

    enum CompressionAlgorithm: String {
        case gzip
        case deflate

        init?(header: String?) {
            switch header {
            case .some("gzip"):
                self = .gzip
            case .some("deflate"):
                self = .deflate
            default:
                return nil
            }
        }

        var window: CInt {
            switch self {
            case .deflate:
                return 15
            case .gzip:
                return 15 + 16
            }
        }
    }

    struct Decompressor {
        private let limit: NIOHTTPDecompression.DecompressionLimit
        private var stream = z_stream()
        private var inflated = 0

        init(limit: NIOHTTPDecompression.DecompressionLimit) {
            self.limit = limit
        }

        mutating func decompress(part: inout ByteBuffer, buffer: inout ByteBuffer, originalLength: Int) throws {
            buffer.reserveCapacity(part.readableBytes * 2)

            self.inflated += try self.stream.inflatePart(input: &part, output: &buffer)

            if self.limit.exceeded(compressed: originalLength, decompressed: self.inflated) {
                throw NIOHTTPDecompression.DecompressionError.limit
            }
        }

        mutating func initializeDecoder(encoding: NIOHTTPDecompression.CompressionAlgorithm, length: Int) throws {
            self.stream.zalloc = nil
            self.stream.zfree = nil
            self.stream.opaque = nil

            let rc = CNIOExtrasZlib_inflateInit2(&self.stream, encoding.window)
            guard rc == Z_OK else {
                throw NIOHTTPDecompression.DecompressionError.initializationError(Int(rc))
            }
        }

        mutating func deinitializeDecoder() {
            inflateEnd(&self.stream)
        }
    }
}

extension z_stream {
    mutating func inflatePart(input: inout ByteBuffer, output: inout ByteBuffer) throws -> Int {
        var written = 0
        try input.readWithUnsafeMutableReadableBytes { pointer in
            self.avail_in = UInt32(pointer.count)
            self.next_in = CNIOExtrasZlib_voidPtr_to_BytefPtr(pointer.baseAddress!)

            defer {
                self.avail_in = 0
                self.next_in = nil
                self.avail_out = 0
                self.next_out = nil
            }

            written += try self.inflatePart(to: &output)

            return pointer.count - Int(self.avail_in)
        }
        return written
    }

    private mutating func inflatePart(to buffer: inout ByteBuffer) throws -> Int {
        return try buffer.writeWithUnsafeMutableBytes { pointer in
            self.avail_out = UInt32(pointer.count)
            self.next_out = CNIOExtrasZlib_voidPtr_to_BytefPtr(pointer.baseAddress!)

            let rc = inflate(&self, Z_NO_FLUSH)
            guard rc == Z_OK || rc == Z_STREAM_END else {
                throw NIOHTTPDecompression.DecompressionError.inflationError(Int(rc))
            }

            return pointer.count - Int(self.avail_out)
        }
    }
}
