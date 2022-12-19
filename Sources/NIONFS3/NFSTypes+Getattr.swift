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

// MARK: - Getattr
public struct NFS3CallGetAttr: Equatable {
    public init(fileHandle: NFS3FileHandle) {
        self.fileHandle = fileHandle
    }

    public var fileHandle: NFS3FileHandle
}

public struct NFS3ReplyGetAttr: Equatable {
    public init(result: NFS3Result<NFS3ReplyGetAttr.Okay, NFS3Nothing>) {
        self.result = result
    }

    public struct Okay: Equatable {
        public init(attributes: NFS3FileAttr) {
            self.attributes = attributes
        }

        public var attributes: NFS3FileAttr
    }

    public var result: NFS3Result<Okay, NFS3Nothing>
}

extension ByteBuffer {
    public mutating func readNFSCallGetattr() throws -> NFS3CallGetAttr {
        let fileHandle = try self.readNFSFileHandle()
        return NFS3CallGetAttr(fileHandle: fileHandle)
    }

    @discardableResult public mutating func writeNFSCallGetattr(_ call: NFS3CallGetAttr) -> Int {
        self.writeNFSFileHandle(call.fileHandle)
    }

    public mutating func readNFSReplyGetAttr() throws -> NFS3ReplyGetAttr {
        return NFS3ReplyGetAttr(
            result: try self.readNFSResult(
                readOkay: { buffer in
                    return NFS3ReplyGetAttr.Okay(attributes: try buffer.readNFSFileAttr())
                },
                readFail: { _ in
                    return NFS3Nothing()
                })
        )
    }

    @discardableResult public mutating func writeNFSReplyGetAttr(_ reply: NFS3ReplyGetAttr) -> Int {
        var bytesWritten = self.writeNFSResultStatus(reply.result)

        switch reply.result {
        case .okay(let okay):
            bytesWritten += self.writeNFSFileAttr(okay.attributes)
        case .fail(_, _):
            ()
        }
        return bytesWritten
    }
}
