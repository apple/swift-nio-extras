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

// MARK: - Unmount
public struct MountCallUnmount: Hashable & Sendable {
    public init(dirPath: String) {
        self.dirPath = dirPath
    }

    public var dirPath: String
}

public struct MountReplyUnmount: Hashable & Sendable {
    public init() {}
}

extension ByteBuffer {
    public mutating func readNFS3CallUnmount() throws -> MountCallUnmount {
        let dirPath = try self.readNFS3String()
        return MountCallUnmount(dirPath: dirPath)
    }

    @discardableResult public mutating func writeNFS3CallUnmount(_ call: MountCallUnmount) -> Int {
        self.writeNFS3String(call.dirPath)
    }

    @discardableResult public mutating func writeNFS3ReplyUnmount(_ reply: MountReplyUnmount) -> Int {
        0
    }

    public mutating func readNFS3ReplyUnmount() throws -> MountReplyUnmount {
        MountReplyUnmount()
    }
}
