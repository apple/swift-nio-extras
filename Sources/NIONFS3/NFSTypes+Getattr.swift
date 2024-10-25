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

// MARK: - Getattr
public struct NFS3CallGetAttr: Hashable & Sendable {
    public init(fileHandle: NFS3FileHandle) {
        self.fileHandle = fileHandle
    }

    public var fileHandle: NFS3FileHandle
}

public struct NFS3ReplyGetAttr: Hashable & Sendable {
    public init(result: NFS3Result<NFS3ReplyGetAttr.Okay, NFS3Nothing>) {
        self.result = result
    }

    public struct Okay: Hashable & Sendable {
        public init(attributes: NFS3FileAttr) {
            self.attributes = attributes
        }

        public var attributes: NFS3FileAttr
    }

    public var result: NFS3Result<Okay, NFS3Nothing>
}

extension ByteBuffer {
    public mutating func readNFS3CallGetattr() throws -> NFS3CallGetAttr {
        let fileHandle = try self.readNFS3FileHandle()
        return NFS3CallGetAttr(fileHandle: fileHandle)
    }

    @discardableResult public mutating func writeNFS3CallGetattr(_ call: NFS3CallGetAttr) -> Int {
        self.writeNFS3FileHandle(call.fileHandle)
    }

    public mutating func readNFS3ReplyGetAttr() throws -> NFS3ReplyGetAttr {
        NFS3ReplyGetAttr(
            result: try self.readNFS3Result(
                readOkay: { buffer in
                    NFS3ReplyGetAttr.Okay(attributes: try buffer.readNFS3FileAttr())
                },
                readFail: { _ in
                    NFS3Nothing()
                }
            )
        )
    }

    @discardableResult public mutating func writeNFS3ReplyGetAttr(_ reply: NFS3ReplyGetAttr) -> Int {
        var bytesWritten = self.writeNFS3ResultStatus(reply.result)

        switch reply.result {
        case .okay(let okay):
            bytesWritten += self.writeNFS3FileAttr(okay.attributes)
        case .fail(_, _):
            ()
        }
        return bytesWritten
    }
}
