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
import NIOHTTP1
import Foundation

// MARK:  Setup
var warning: String = ""
assert({
    print("============================================================")
    print("= YOU ARE RUNNING NIOExtrasPerformanceTester IN DEBUG MODE =")
    print("============================================================")
    warning = " <<< DEBUG MODE >>>"
    return true
    }())

// MARK:  Tests
try! measureAndPrint(desc: "http1_threaded_50reqs_500conns",
                     benchmark: HTTP1ThreadedRawPerformanceTest())

try! measureAndPrint(desc: "http1_threaded_50reqs_500conns_rolling_pcap",
                     benchmark: HTTP1ThreadedRollingPCapPerformanceTest())

try! measureAndPrint(desc: "http1_threaded_50reqs_500conns_pcap",
                     benchmark: HTTP1ThreadedPCapPerformanceTest())
