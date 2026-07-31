//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2026 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CNIOExtrasZlib
import NIOCore
import XCTest

@testable import NIOHTTPCompression

final class ZlibStreamLifecycleTest: XCTestCase {
    func testDecompressorCanInitializeAfterInitializationFailure() throws {
        let decompressor = NIOHTTPDecompression.Decompressor(limit: .none)

        XCTAssertThrowsError(try decompressor.initializeDecoder(windowBits: 100)) { error in
            XCTAssertEqual(
                error as? NIOHTTPDecompression.DecompressionError,
                .initializationError(Int(CNIOEXTRAS_Z_STREAM_ERROR))
            )
        }

        XCTAssertNoThrow(try decompressor.initializeDecoder())
        XCTAssertEqual(decompressor.deinitializeDecoder(), CNIOEXTRAS_Z_OK)
        // Explicit deinitialization is idempotent so the stream owner cannot call inflateEnd twice.
        XCTAssertNil(decompressor.deinitializeDecoder())
    }

    func testStreamOwnersSupportMultipleCompressionLifecycles() throws {
        let allocator = ByteBufferAllocator()
        let compressor = NIOCompression.Compressor()
        let decompressor = NIOHTTPDecompression.Decompressor(limit: .none)

        for (encoding, chunks) in [
            (NIOCompression.Algorithm.gzip, ["first compression ", "lifecycle"]),
            (NIOCompression.Algorithm.deflate, ["second compression ", "lifecycle"]),
        ] {
            compressor.initialize(encoding: encoding)
            XCTAssertTrue(compressor.zlibStateIsAllocated)
            var firstInput = allocator.buffer(capacity: chunks[0].utf8.count)
            firstInput.writeString(chunks[0])
            var compressed = compressor.compress(inputBuffer: &firstInput, allocator: allocator, finalise: false)

            var secondInput = allocator.buffer(capacity: chunks[1].utf8.count)
            secondInput.writeString(chunks[1])
            var finalCompressed = compressor.compress(inputBuffer: &secondInput, allocator: allocator, finalise: true)
            compressed.writeBuffer(&finalCompressed)
            XCTAssertEqual(compressor.shutdown(), CNIOEXTRAS_Z_OK)
            XCTAssertNil(compressor.shutdownIfActive())
            XCTAssertFalse(compressor.zlibStateIsAllocated)

            let text = chunks.joined()
            let compressedLength = compressed.readableBytes
            var firstCompressedPart = compressed.readSlice(length: compressedLength / 2)!
            var output = allocator.buffer(capacity: text.utf8.count)
            try decompressor.initializeDecoder()
            XCTAssertTrue(decompressor.zlibStateIsAllocated)
            let firstResult = try decompressor.decompress(
                part: &firstCompressedPart,
                buffer: &output,
                compressedLength: compressedLength
            )
            let finalResult = try decompressor.decompress(
                part: &compressed,
                buffer: &output,
                compressedLength: compressedLength
            )
            XCTAssertEqual(decompressor.deinitializeDecoder(), CNIOEXTRAS_Z_OK)
            XCTAssertFalse(decompressor.zlibStateIsAllocated)

            XCTAssertFalse(firstResult.complete)
            XCTAssertTrue(finalResult.complete)
            XCTAssertEqual(firstCompressedPart.readableBytes, 0)
            XCTAssertEqual(compressed.readableBytes, 0)
            XCTAssertEqual(output.readString(length: output.readableBytes), text)
        }
    }

    func testActiveStreamsAreCleanedUpOnDeinit() throws {
        weak var weakCompressor: NIOCompression.Compressor?
        weak var weakDecompressor: NIOHTTPDecompression.Decompressor?

        do {
            let compressor = NIOCompression.Compressor()
            compressor.initialize(encoding: .gzip)
            weakCompressor = compressor

            let decompressor = NIOHTTPDecompression.Decompressor(limit: .none)
            try decompressor.initializeDecoder()
            weakDecompressor = decompressor
        }

        XCTAssertNil(weakCompressor)
        XCTAssertNil(weakDecompressor)
    }
}
