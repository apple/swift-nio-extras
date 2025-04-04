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

import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOExtras

class HTTP1ThreadedPCapPerformanceTest: HTTP1ThreadedPerformanceTest {
    private final class SinkHolder: Sendable {
        let fileSink: NIOLoopBound<NIOWritePCAPHandler.SynchronizedFileSink>
        let eventLoop: any EventLoop

        init(eventLoop: any EventLoop) {
            self.eventLoop = eventLoop

            let outputFile = NSTemporaryDirectory() + "/" + UUID().uuidString
            let fileSink = try! NIOWritePCAPHandler.SynchronizedFileSink.fileSinkWritingToFile(path: outputFile) {
                error in
                print("ERROR: \(error)")
                exit(1)
            }

            self.fileSink = NIOLoopBound(fileSink, eventLoop: eventLoop)
        }

        func tearDown() -> EventLoopFuture<Void> {
            self.eventLoop.submit {
                try self.fileSink.value.syncClose()
            }
        }
    }

    init() {
        let sinkHolders = NIOLockedValueBox<[SinkHolder]>([])
        self.sinkHolders = sinkHolders
        super.init(
            numberOfRepeats: 50,
            numberOfClients: System.coreCount,
            requestsPerClient: 500,
            extraInitialiser: { channel in
                channel.eventLoop.makeCompletedFuture {
                    let sinkHolder = SinkHolder(eventLoop: channel.eventLoop)
                    sinkHolders.withLockedValue { $0.append(sinkHolder) }

                    let pcapHandler = NIOWritePCAPHandler(
                        mode: .client,
                        fileSink: sinkHolder.fileSink.value.write(buffer:)
                    )
                    return try channel.pipeline.syncOperations.addHandler(pcapHandler, position: .first)
                }
            }
        )
    }

    private let sinkHolders: NIOLockedValueBox<[SinkHolder]>

    override func run() throws -> Int {
        let result = Result {
            try super.run()
        }

        let holders = self.sinkHolders.withLockedValue { $0 }
        for holder in holders {
            try holder.tearDown().wait()
        }

        return try result.get()
    }
}
