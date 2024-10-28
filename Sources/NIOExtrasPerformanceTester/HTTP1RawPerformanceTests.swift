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
import NIOHTTP1

class HTTP1ThreadedRawPerformanceTest: HTTP1ThreadedPerformanceTest {
    init() {
        super.init(
            numberOfRepeats: 50,
            numberOfClients: System.coreCount,
            requestsPerClient: 500,
            extraInitialiser: { channel in channel.eventLoop.makeSucceededFuture(()) }
        )
    }
}
