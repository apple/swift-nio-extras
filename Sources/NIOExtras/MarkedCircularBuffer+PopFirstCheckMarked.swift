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

import NIOCore

extension MarkedCircularBuffer {
    @inlinable
    internal mutating func popFirstCheckMarked() -> (Element, Bool)? {
        let marked = self.markedElementIndex == self.startIndex
        return self.popFirst().map { ($0, marked) }
    }
}
