//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import NIOCore
import NIOEmbedded
import XCTest

@testable import NIOExtras

final class SynchronizedFileSinkTests: XCTestCase {
    func testSimpleFileSink() throws {
        try withTemporaryFile { file, path in
            let sink = try NIOWritePCAPHandler.SynchronizedFileSink.fileSinkWritingToFile(
                path: path,
                errorHandler: { XCTFail("Caught error \($0)") }
            )

            sink.write(buffer: ByteBuffer(string: "Hello, "))
            sink.write(buffer: ByteBuffer(string: "world!"))
            try sink.syncClose()

            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            XCTAssertEqual(
                data,
                Data(NIOWritePCAPHandler.pcapFileHeader.readableBytesView) + Data("Hello, world!".utf8)
            )
        }
    }

    func testSimpleFileSinkAsyncShutdown() throws {
        guard #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) else { return }
        XCTAsyncTest {
            try await withTemporaryFile { file, path in
                let sink = try NIOWritePCAPHandler.SynchronizedFileSink.fileSinkWritingToFile(
                    path: path,
                    errorHandler: { XCTFail("Caught error \($0)") }
                )

                sink.write(buffer: ByteBuffer(string: "Hello, "))
                sink.write(buffer: ByteBuffer(string: "world!"))
                try await sink.close()

                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                XCTAssertEqual(
                    data,
                    Data(NIOWritePCAPHandler.pcapFileHeader.readableBytesView) + Data("Hello, world!".utf8)
                )
            }
        }
    }
}

private func withTemporaryFile<T>(
    content: String? = nil,
    _ body: (NIOCore.NIOFileHandle, String) throws -> T
) throws -> T {
    let temporaryFilePath = "\(temporaryDirectory)/nio_extras_\(UUID())"
    XCTAssertTrue(FileManager.default.createFile(atPath: temporaryFilePath, contents: content?.data(using: .utf8)))
    defer {
        XCTAssertNoThrow(try FileManager.default.removeItem(atPath: temporaryFilePath))
    }

    let fileHandle = try NIOFileHandle(_deprecatedPath: temporaryFilePath, mode: [.read, .write])
    defer {
        XCTAssertNoThrow(try fileHandle.close())
    }

    return try body(fileHandle, temporaryFilePath)
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
private func withTemporaryFile<T>(
    content: String? = nil,
    _ body: (NIOCore.NIOFileHandle, String) async throws -> T
) async throws -> T {
    let temporaryFilePath = "\(temporaryDirectory)/nio_extras_\(UUID())"
    XCTAssertTrue(FileManager.default.createFile(atPath: temporaryFilePath, contents: content?.data(using: .utf8)))
    defer {
        XCTAssertNoThrow(try FileManager.default.removeItem(atPath: temporaryFilePath))
    }

    // NIOFileHandle(_deprecatedPath:mode:) is 'noasync' but we don't have a viable alternative;
    // this wrapper suppresses the 'noasync'.
    func makeFileHandle() throws -> NIOFileHandle {
        try NIOFileHandle(_deprecatedPath: temporaryFilePath, mode: [.read, .write])
    }

    let fileHandle = try makeFileHandle()
    defer {
        XCTAssertNoThrow(try fileHandle.close())
    }

    return try await body(fileHandle, temporaryFilePath)
}

private var temporaryDirectory: String {
    #if os(Linux)
    return "/tmp"
    #elseif os(Android)
    return "/data/local/tmp"
    #else
    if #available(macOS 10.12, iOS 10, tvOS 10, watchOS 3, *) {
        return FileManager.default.temporaryDirectory.path
    } else {
        return "/tmp"
    }
    #endif  // os
}

extension XCTestCase {
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    /// Cross-platform XCTest support for async-await tests.
    ///
    /// Currently the Linux implementation of XCTest doesn't have async-await support.
    /// Until it does, we make use of this shim which uses a detached `Task` along with
    /// `XCTest.wait(for:timeout:)` to wrap the operation.
    ///
    /// - NOTE: Support for Linux is tracked by https://bugs.swift.org/browse/SR-14403.
    /// - NOTE: Implementation currently in progress: https://github.com/apple/swift-corelibs-xctest/pull/326
    func XCTAsyncTest(
        expectationDescription: String = "Async operation",
        timeout: TimeInterval = 30,
        file: StaticString = #filePath,
        line: UInt = #line,
        function: StaticString = #function,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        let expectation = self.expectation(description: expectationDescription)
        Task {
            do {
                try await operation()
            } catch {
                XCTFail("Error thrown while executing \(function): \(error)", file: file, line: line)
                for callStack in Thread.callStackSymbols { print(callStack) }
            }
            expectation.fulfill()
        }
        self.wait(for: [expectation], timeout: timeout)
    }
}
