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
import NIOExtras
import Foundation

class PCAPPerformanceTest: Benchmark {
    let numberOfRepeats: Int

    let byteBuffer = ByteBuffer(repeating: 0x65, count: 1000)

    init(numberOfRepeats: Int) {
        self.numberOfRepeats = numberOfRepeats
    }

    var outputFile: String!

    func setUp() throws {
        self.outputFile = NSTemporaryDirectory() + "/" + UUID().uuidString
    }

    func tearDown() {
        try! FileManager.default.removeItem(atPath: self.outputFile)
    }
    
    func run() throws -> Int {
        let fileSink = try NIOWritePCAPHandler.SynchronizedFileSink.fileSinkWritingToFile(path: self.outputFile) {
            error in
            print("ERROR: \(error)")
            exit(1)
        }
        defer {
            try! fileSink.syncClose()  // We want this to be included in the timing.
        }

        let channel = EmbeddedChannel()
        defer {
            _ = try! channel.finish()
        }

        let pcapHandler = NIOWritePCAPHandler(mode: .client,
                                              fileSink: fileSink.write)
        try channel.pipeline.addHandler(pcapHandler, position: .first).wait()


        for _ in 0 ..< self.numberOfRepeats {
            channel.writeAndFlush(self.byteBuffer, promise: nil)
            _ = try channel.readOutbound(as: ByteBuffer.self)
        }
        return self.numberOfRepeats
    }
}
