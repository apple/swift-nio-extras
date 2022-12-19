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

// MARK: - Readlink
public struct NFS3CallReadlink: Equatable {
    public init(symlink: NFS3FileHandle) {
        self.symlink = symlink
    }

    public var symlink: NFS3FileHandle
}

public struct NFS3ReplyReadlink: Equatable {
    public init(result: NFS3Result<NFS3ReplyReadlink.Okay, NFS3ReplyReadlink.Fail>) {
        self.result = result
    }

    public struct Okay: Equatable {
        public init(symlinkAttributes: NFS3FileAttr? = nil, target: String) {
            self.symlinkAttributes = symlinkAttributes
            self.target = target
        }

        public var symlinkAttributes: NFS3FileAttr?
        public var target: String
    }

    public struct Fail: Equatable {
        public init(symlinkAttributes: NFS3FileAttr? = nil) {
            self.symlinkAttributes = symlinkAttributes
        }

        public var symlinkAttributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFSCallReadlink() throws -> NFS3CallReadlink {
        let symlink = try self.readNFSFileHandle()

        return .init(symlink: symlink)
    }

    @discardableResult public mutating func writeNFSCallReadlink(_ call: NFS3CallReadlink) -> Int {
        self.writeNFSFileHandle(call.symlink)
    }

    public mutating func readNFSReplyReadlink() throws -> NFS3ReplyReadlink {
        return NFS3ReplyReadlink(
            result: try self.readNFSResult(
                readOkay: { buffer in
                    let attrs = try buffer.readNFSOptional { try $0.readNFSFileAttr() }
                    let target = try buffer.readNFSString()

                    return NFS3ReplyReadlink.Okay(symlinkAttributes: attrs, target: target)
                },
                readFail: { buffer in
                    let attrs = try buffer.readNFSOptional { try $0.readNFSFileAttr() }
                    return NFS3ReplyReadlink.Fail(symlinkAttributes: attrs)
                }))
    }

    @discardableResult public mutating func writeNFSReplyReadlink(_ reply: NFS3ReplyReadlink) -> Int {
        var bytesWritten = self.writeNFSResultStatus(reply.result)

        switch reply.result {
        case .okay(let okay):
            bytesWritten += self.writeNFSOptional(okay.symlinkAttributes, writer: { $0.writeNFSFileAttr($1) })
            + self.writeNFSString(okay.target)
        case .fail(_, let fail):
            bytesWritten += self.writeNFSOptional(fail.symlinkAttributes, writer: { $0.writeNFSFileAttr($1) })
        }
        return bytesWritten
    }
}
