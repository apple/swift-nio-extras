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

class HTTP1ThreadedRollingPCapPerformanceTest: HTTP1ThreadedPerformanceTest {
    init() {
        func addRollingPCap(channel: Channel) -> EventLoopFuture<Void> {
            let pcapRingBuffer = NIOPCAPRingBuffer(maximumFragments: 25,
                                                   maximumBytes: 1_000_000)
            let pcapHandler = NIOWritePCAPHandler(mode: .client,
                                                  fileSink: pcapRingBuffer.addFragment)
            return channel.pipeline.addHandler(pcapHandler, position: .first)
        }

        super.init(numberOfRepeats: 50,
                   numberOfClients: System.coreCount,
                   requestsPerClient: 500,
                   extraInitialiser: { channel in return addRollingPCap(channel: channel) })
    }
}
