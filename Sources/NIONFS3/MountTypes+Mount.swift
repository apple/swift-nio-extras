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

// MARK: - Mount
public struct MountCallMount: Equatable {
    public init(dirPath: String) {
        self.dirPath = dirPath
    }

    public var dirPath: String
}

public struct MountReplyMount: Equatable {
    public init(result: NFS3Result<MountReplyMount.Okay, NFS3Nothing>) {
        self.result = result
    }

    public struct Okay: Equatable {
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
    public mutating func readNFSCallMount() throws -> MountCallMount {
        let dirPath = try self.readNFSString()
        return MountCallMount(dirPath: dirPath)
    }

    @discardableResult public mutating func writeNFSCallMount(_ call: MountCallMount) -> Int {
        self.writeNFSString(call.dirPath)
    }

    @discardableResult public mutating func writeNFSReplyMount(_ reply: MountReplyMount) -> Int {
        var bytesWritten = self.writeNFSResultStatus(reply.result)

        switch reply.result {
        case .okay(let reply):
            bytesWritten += self.writeNFSFileHandle(reply.fileHandle)
            precondition(reply.authFlavors == [.unix] || reply.authFlavors == [.noAuth],
                         "Sorry, anything but [.unix] / [.system] / [.noAuth] unimplemented.")
            bytesWritten += self.writeInteger(UInt32(reply.authFlavors.count), endianness: .big, as: UInt32.self)
            for flavor in reply.authFlavors {
                bytesWritten += self.writeInteger(flavor.rawValue, endianness: .big, as: UInt32.self)
            }
        case .fail(_, _):
            ()
        }

        return bytesWritten
    }

    public mutating func readNFSReplyMount() throws -> MountReplyMount {
        let result = try self.readNFSResult(readOkay: { buffer in
            let fileHandle = try buffer.readNFSFileHandle()
            let authFlavors = try buffer.readNFSList(readEntry: { buffer in
                try buffer.readRPCAuthFlavor()
            })
            return MountReplyMount.Okay(fileHandle: fileHandle, authFlavors: authFlavors)

        },
                                            readFail: { _ in NFS3Nothing() })
        return MountReplyMount(result: result)
    }
}
