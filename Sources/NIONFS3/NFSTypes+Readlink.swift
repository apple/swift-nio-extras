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

// MARK: - Readlink
public struct NFS3CallReadlink: Hashable & Sendable {
    public init(symlink: NFS3FileHandle) {
        self.symlink = symlink
    }

    public var symlink: NFS3FileHandle
}

public struct NFS3ReplyReadlink: Hashable & Sendable {
    public init(result: NFS3Result<NFS3ReplyReadlink.Okay, NFS3ReplyReadlink.Fail>) {
        self.result = result
    }

    public struct Okay: Hashable & Sendable {
        public init(symlinkAttributes: NFS3FileAttr? = nil, target: String) {
            self.symlinkAttributes = symlinkAttributes
            self.target = target
        }

        public var symlinkAttributes: NFS3FileAttr?
        public var target: String
    }

    public struct Fail: Hashable & Sendable {
        public init(symlinkAttributes: NFS3FileAttr? = nil) {
            self.symlinkAttributes = symlinkAttributes
        }

        public var symlinkAttributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFS3CallReadlink() throws -> NFS3CallReadlink {
        let symlink = try self.readNFS3FileHandle()

        return .init(symlink: symlink)
    }

    @discardableResult public mutating func writeNFS3CallReadlink(_ call: NFS3CallReadlink) -> Int {
        self.writeNFS3FileHandle(call.symlink)
    }

    public mutating func readNFS3ReplyReadlink() throws -> NFS3ReplyReadlink {
        NFS3ReplyReadlink(
            result: try self.readNFS3Result(
                readOkay: { buffer in
                    let attrs = try buffer.readNFS3Optional { try $0.readNFS3FileAttr() }
                    let target = try buffer.readNFS3String()

                    return NFS3ReplyReadlink.Okay(symlinkAttributes: attrs, target: target)
                },
                readFail: { buffer in
                    let attrs = try buffer.readNFS3Optional { try $0.readNFS3FileAttr() }
                    return NFS3ReplyReadlink.Fail(symlinkAttributes: attrs)
                }
            )
        )
    }

    @discardableResult public mutating func writeNFS3ReplyReadlink(_ reply: NFS3ReplyReadlink) -> Int {
        var bytesWritten = self.writeNFS3ResultStatus(reply.result)

        switch reply.result {
        case .okay(let okay):
            bytesWritten +=
                self.writeNFS3Optional(okay.symlinkAttributes, writer: { $0.writeNFS3FileAttr($1) })
                + self.writeNFS3String(okay.target)
        case .fail(_, let fail):
            bytesWritten += self.writeNFS3Optional(fail.symlinkAttributes, writer: { $0.writeNFS3FileAttr($1) })
        }
        return bytesWritten
    }
}
