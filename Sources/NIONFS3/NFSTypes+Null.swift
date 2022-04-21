//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the SwiftNIO project authors
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
public struct NFS3CallNull: Equatable {
    public init() {}
}

extension ByteBuffer {
    public mutating func readNFSCallNull() throws -> NFS3CallNull {
        return NFS3CallNull()
    }

    public mutating func writeNFSCallNull(_ call: NFS3CallNull) {
    }
}
