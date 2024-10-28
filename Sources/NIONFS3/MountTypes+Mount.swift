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

// MARK: - Mount
public struct MountCallMount: Hashable & Sendable {
    public init(dirPath: String) {
        self.dirPath = dirPath
    }

    public var dirPath: String
}

public struct MountReplyMount: Hashable & Sendable {
    public init(result: NFS3Result<MountReplyMount.Okay, NFS3Nothing>) {
        self.result = result
    }

    public struct Okay: Hashable & Sendable {
        public init(fileHandle: NFS3FileHandle, authFlavors: [RPCAuthFlavor] = [.unix]) {
            self.fileHandle = fileHandle
            self.authFlavors = authFlavors
        }

        public var fileHandle: NFS3FileHandle
        public var authFlavors: [RPCAuthFlavor] = [.unix]
    }

    public var result: NFS3Result<Okay, NFS3Nothing>
}

extension ByteBuffer {
    public mutating func readNFS3CallMount() throws -> MountCallMount {
        let dirPath = try self.readNFS3String()
        return MountCallMount(dirPath: dirPath)
    }

    @discardableResult public mutating func writeNFS3CallMount(_ call: MountCallMount) -> Int {
        self.writeNFS3String(call.dirPath)
    }

    @discardableResult public mutating func writeNFS3ReplyMount(_ reply: MountReplyMount) -> Int {
        var bytesWritten = self.writeNFS3ResultStatus(reply.result)

        switch reply.result {
        case .okay(let reply):
            bytesWritten += self.writeNFS3FileHandle(reply.fileHandle)
            precondition(
                reply.authFlavors == [.unix] || reply.authFlavors == [.noAuth],
                "Sorry, anything but [.unix] / [.system] / [.noAuth] unimplemented."
            )
            bytesWritten += self.writeInteger(UInt32(reply.authFlavors.count), as: UInt32.self)
            for flavor in reply.authFlavors {
                bytesWritten += self.writeInteger(flavor.rawValue, as: UInt32.self)
            }
        case .fail(_, _):
            ()
        }

        return bytesWritten
    }

    public mutating func readNFS3ReplyMount() throws -> MountReplyMount {
        let result = try self.readNFS3Result(
            readOkay: { buffer -> MountReplyMount.Okay in
                let fileHandle = try buffer.readNFS3FileHandle()
                let authFlavors = try buffer.readNFS3List(readEntry: { buffer in
                    try buffer.readRPCAuthFlavor()
                })
                return MountReplyMount.Okay(fileHandle: fileHandle, authFlavors: authFlavors)

            },
            readFail: { _ in NFS3Nothing() }
        )
        return MountReplyMount(result: result)
    }
}
