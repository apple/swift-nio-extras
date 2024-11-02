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

import Dispatch
import NIOCore

public func measure(_ fn: () throws -> Int) rethrows -> [Double] {
    func measureOne(_ fn: () throws -> Int) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        _ = try fn()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / Double(TimeAmount.seconds(1).nanoseconds)
    }

    _ = try measureOne(fn)  // pre-heat and throw away
    var measurements = Array(repeating: 0.0, count: 10)
    for i in 0..<10 {
        measurements[i] = try measureOne(fn)
    }

    return measurements
}

public func measureAndPrint(desc: String, fn: () throws -> Int) rethrows {
    print("measuring\(warning): \(desc): ", terminator: "")
    let measurements = try measure(fn)
    print(measurements.reduce(into: "") { $0.append("\($1), ") })
}
