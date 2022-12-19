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

// MARK: - Unmount
public struct MountCallUnmount: Equatable {
    public init(dirPath: String) {
        self.dirPath = dirPath
    }

    public var dirPath: String
}

public struct MountReplyUnmount: Equatable {
    public init() {}
}

extension ByteBuffer {
    public mutating func readNFSCallUnmount() throws -> MountCallUnmount {
        let dirPath = try self.readNFSString()
        return MountCallUnmount(dirPath: dirPath)
    }

    @discardableResult public mutating func writeNFSCallUnmount(_ call: MountCallUnmount) -> Int {
        self.writeNFSString(call.dirPath)
    }

    @discardableResult public mutating func writeNFSReplyUnmount(_ reply: MountReplyUnmount) -> Int {
        return 0
    }

    public mutating func readNFSReplyUnmount() throws -> MountReplyUnmount {
        return MountReplyUnmount()
    }
}
