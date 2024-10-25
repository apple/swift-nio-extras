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

// MARK:  Setup
let warning: String = {
    var warning: String = ""
    assert(
        {
            print("============================================================")
            print("= YOU ARE RUNNING NIOExtrasPerformanceTester IN DEBUG MODE =")
            print("============================================================")
            warning = " <<< DEBUG MODE >>>"
            return true
        }()
    )
    return warning
}()

// MARK:  Tests
// Test PCAP to file.
try! measureAndPrint(desc: "pcap_100k_reqs", benchmark: PCAPPerformanceTest(numberOfRepeats: 100_000))

// Test Rolling PCAP never writing to file.
try! measureAndPrint(desc: "rolling_pcap_100k_reqs", benchmark: RollingPCAPPerformanceTest(numberOfRepeats: 100_000))

// Relatively real world test - http1 with many threads.
try! measureAndPrint(
    desc: "http1_threaded_50reqs_500conns",
    benchmark: HTTP1ThreadedRawPerformanceTest()
)

// Relatively real world test - http1 with many threads and rolling pcap.
try! measureAndPrint(
    desc: "http1_threaded_50reqs_500conns_rolling_pcap",
    benchmark: HTTP1ThreadedRollingPCapPerformanceTest()
)

// Relatively real world test - http1 with many threads and pcap to file.
try! measureAndPrint(
    desc: "http1_threaded_50reqs_500conns_pcap",
    benchmark: HTTP1ThreadedPCapPerformanceTest()
)
