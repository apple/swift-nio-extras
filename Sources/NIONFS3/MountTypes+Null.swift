//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

// MARK: - Null
public struct MountCallNull: Hashable & Sendable {
    public init() {}
}

extension ByteBuffer {
    public mutating func readMountCallNull() throws -> MountCallNull {
        MountCallNull()
    }

    @discardableResult public mutating func writeMountCallNull(_ call: MountCallNull) -> Int {
        0
    }
}
