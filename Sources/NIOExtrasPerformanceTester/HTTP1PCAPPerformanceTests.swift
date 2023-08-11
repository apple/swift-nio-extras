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
import NIOExtras
import Foundation

class HTTP1ThreadedPCapPerformanceTest: HTTP1ThreadedPerformanceTest {
    private final class SinkHolder: Sendable {
        let fileSink: NIOLockedValueBox<NIOWritePCAPHandler.SynchronizedFileSink?> = .init(nil)

        func setUp() throws {
            let outputFile = NSTemporaryDirectory() + "/" + UUID().uuidString
            try self.fileSink.withLockedValue {
                $0 = try NIOWritePCAPHandler.SynchronizedFileSink.fileSinkWritingToFile(path: outputFile) { error in
                    print("ERROR: \(error)")
                    exit(1)
                }
            }
        }

        func tearDown() {
            try! self.fileSink.withLockedValue { try $0!.syncClose() }
        }
    }

    init() {
        let sinkHolder = SinkHolder()
        let addPCap: @Sendable (Channel) -> EventLoopFuture<Void> = { channel in
            let pcapHandler = NIOWritePCAPHandler(
                mode: .client,
                fileSink: sinkHolder.fileSink.withLockedValue { $0!.write }
            )
            return channel.pipeline.addHandler(pcapHandler, position: .first)
        }

        self.sinkHolder = sinkHolder
        super.init(
            numberOfRepeats: 50,
            numberOfClients: System.coreCount,
            requestsPerClient: 500,
            extraInitialiser: { channel in addPCap(channel) }
        )
    }

    private let sinkHolder: SinkHolder

    override func run() throws -> Int {
        // Opening and closing the file included here as flushing data to disk is not known to complete until closed.
        try sinkHolder.setUp()
        defer {
            sinkHolder.tearDown()
        }
        return try super.run()
    }
}
