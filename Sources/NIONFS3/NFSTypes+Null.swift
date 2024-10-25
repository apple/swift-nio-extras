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
public struct NFS3CallNull: Hashable & Sendable {
    public init() {}
}

extension ByteBuffer {
    public mutating func readNFS3CallNull() throws -> NFS3CallNull {
        NFS3CallNull()
    }

    @discardableResult public mutating func writeNFS3CallNull(_ call: NFS3CallNull) -> Int {
        0
    }
}
