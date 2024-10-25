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

// MARK: - Setattr
public struct NFS3CallSetattr: Hashable & Sendable {
    public init(object: NFS3FileHandle, newAttributes: NFS3CallSetattr.Attributes, guard: NFS3Time? = nil) {
        self.object = object
        self.newAttributes = newAttributes
        self.guard = `guard`
    }

    public struct Attributes: Hashable & Sendable {
        public init(
            mode: NFS3FileMode? = nil,
            uid: NFS3UID? = nil,
            gid: NFS3GID? = nil,
            size: NFS3Size? = nil,
            atime: NFS3Time? = nil,
            mtime: NFS3Time? = nil
        ) {
            self.mode = mode
            self.uid = uid
            self.gid = gid
            self.size = size
            self.atime = atime
            self.mtime = mtime
        }

        public var mode: NFS3FileMode?
        public var uid: NFS3UID?
        public var gid: NFS3GID?
        public var size: NFS3Size?
        public var atime: NFS3Time?
        public var mtime: NFS3Time?

    }
    public var object: NFS3FileHandle
    public var newAttributes: Attributes
    public var `guard`: NFS3Time?
}

public struct NFS3ReplySetattr: Hashable & Sendable {
    public init(result: NFS3Result<NFS3ReplySetattr.Okay, NFS3ReplySetattr.Fail>) {
        self.result = result
    }

    public struct Okay: Hashable & Sendable {
        public init(wcc: NFS3WeakCacheConsistencyData) {
            self.wcc = wcc
        }

        public var wcc: NFS3WeakCacheConsistencyData
    }

    public struct Fail: Hashable & Sendable {
        public init(wcc: NFS3WeakCacheConsistencyData) {
            self.wcc = wcc
        }

        public var wcc: NFS3WeakCacheConsistencyData
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    private mutating func readNFS3CallSetattrAttributes() throws -> NFS3CallSetattr.Attributes {
        let mode = try self.readNFS3Optional { try $0.readNFS3FileMode() }
        let uid = try self.readNFS3Optional { try $0.readNFS3UID() }
        let gid = try self.readNFS3Optional { try $0.readNFS3GID() }
        let size = try self.readNFS3Optional { try $0.readNFS3Size() }
        let atime = try self.readNFS3Optional { try $0.readNFS3Time() }
        let mtime = try self.readNFS3Optional { try $0.readNFS3Time() }

        return .init(mode: mode, uid: uid, gid: gid, size: size, atime: atime, mtime: mtime)
    }

    private mutating func writeNFS3CallSetattrAttributes(_ attrs: NFS3CallSetattr.Attributes) -> Int {
        self.writeNFS3Optional(attrs.mode, writer: { $0.writeNFS3FileMode($1) })
            + self.writeNFS3Optional(attrs.uid, writer: { $0.writeNFS3UID($1) })
            + self.writeNFS3Optional(attrs.gid, writer: { $0.writeNFS3GID($1) })
            + self.writeNFS3Optional(attrs.size, writer: { $0.writeNFS3Size($1) })
            + self.writeNFS3Optional(attrs.atime, writer: { $0.writeNFS3Time($1) })
            + self.writeNFS3Optional(attrs.mtime, writer: { $0.writeNFS3Time($1) })
    }

    public mutating func readNFS3CallSetattr() throws -> NFS3CallSetattr {
        let object = try self.readNFS3FileHandle()
        let attributes = try self.readNFS3CallSetattrAttributes()
        let `guard` = try self.readNFS3Optional { try $0.readNFS3Time() }

        return .init(object: object, newAttributes: attributes, guard: `guard`)
    }

    @discardableResult public mutating func writeNFS3CallSetattr(_ call: NFS3CallSetattr) -> Int {
        self.writeNFS3FileHandle(call.object)
            + self.writeNFS3CallSetattrAttributes(call.newAttributes)
            + self.writeNFS3Optional(call.guard, writer: { $0.writeNFS3Time($1) })
    }

    public mutating func readNFS3ReplySetattr() throws -> NFS3ReplySetattr {
        NFS3ReplySetattr(
            result: try self.readNFS3Result(
                readOkay: { buffer in
                    NFS3ReplySetattr.Okay(wcc: try buffer.readNFS3WeakCacheConsistencyData())
                },
                readFail: { buffer in
                    NFS3ReplySetattr.Fail(wcc: try buffer.readNFS3WeakCacheConsistencyData())
                }
            )
        )
    }

    @discardableResult public mutating func writeNFS3ReplySetattr(_ reply: NFS3ReplySetattr) -> Int {
        var bytesWritten = self.writeNFS3ResultStatus(reply.result)

        switch reply.result {
        case .okay(let okay):
            bytesWritten += self.writeNFS3WeakCacheConsistencyData(okay.wcc)
        case .fail(_, let fail):
            bytesWritten += self.writeNFS3WeakCacheConsistencyData(fail.wcc)
        }
        return bytesWritten
    }
}
