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

import NIOCore
import NIOExtras
import Foundation

class HTTP1ThreadedPCapPerformanceTest: HTTP1ThreadedPerformanceTest {
    private class SinkHolder {
        var fileSink: NIOWritePCAPHandler.SynchronizedFileSink!

        func setUp() throws {
            let outputFile = NSTemporaryDirectory() + "/" + UUID().uuidString
            self.fileSink = try NIOWritePCAPHandler.SynchronizedFileSink.fileSinkWritingToFile(path: outputFile) { error in
                print("ERROR: \(error)")
                exit(1)
            }
        }

        func tearDown() {
            try! self.fileSink.syncClose()
        }
    }

    init() {
        let sinkHolder = SinkHolder()
        func addPCap(channel: Channel) -> EventLoopFuture<Void> {
            let pcapHandler = NIOWritePCAPHandler(mode: .client,
                                                  fileSink: sinkHolder.fileSink.write)
            return channel.pipeline.addHandler(pcapHandler, position: .first)
        }

        self.sinkHolder = sinkHolder
        super.init(numberOfRepeats: 50,
                   numberOfClients: System.coreCount,
                   requestsPerClient: 500,
                   extraInitialiser: { channel in return addPCap(channel: channel) })
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
