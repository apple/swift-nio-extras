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

// MARK: - Setattr
public struct NFS3CallSetattr: Hashable {
    public init(object: NFS3FileHandle, newAttributes: NFS3CallSetattr.Attributes, guard: NFS3Time? = nil) {
        self.object = object
        self.newAttributes = newAttributes
        self.guard = `guard`
    }

    public struct Attributes: Hashable {
        public init(mode: NFS3FileMode? = nil, uid: NFS3UID? = nil, gid: NFS3GID? = nil, size: NFS3Size? = nil, atime: NFS3Time? = nil, mtime: NFS3Time? = nil) {
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

public struct NFS3ReplySetattr: Hashable {
    public init(result: NFS3Result<NFS3ReplySetattr.Okay, NFS3ReplySetattr.Fail>) {
        self.result = result
    }

    public struct Okay: Hashable {
        public init(wcc: NFS3WeakCacheConsistencyData) {
            self.wcc = wcc
        }

        public var wcc: NFS3WeakCacheConsistencyData
    }

    public struct Fail: Hashable {
        public init(wcc: NFS3WeakCacheConsistencyData) {
            self.wcc = wcc
        }

        public var wcc: NFS3WeakCacheConsistencyData
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    private mutating func readNFSCallSetattrAttributes() throws -> NFS3CallSetattr.Attributes {
        let mode = try self.readNFSOptional { try $0.readNFSInteger(as: UInt32.self) }
        let uid = try self.readNFSOptional { try $0.readNFSInteger(as: UInt32.self) }
        let gid = try self.readNFSOptional { try $0.readNFSInteger(as: UInt32.self) }
        let size = try self.readNFSOptional { try $0.readNFSInteger(as: UInt64.self) }
        let atime = try self.readNFSOptional { try $0.readNFSTime() }
        let mtime = try self.readNFSOptional { try $0.readNFSTime() }

        return .init(mode: mode, uid: uid, gid: gid, size: size, atime: atime, mtime: mtime)
    }

    private mutating func writeNFSCallSetattrAttributes(_ attrs: NFS3CallSetattr.Attributes) -> Int {
        return self.writeNFSOptional(attrs.mode, writer: { $0.writeInteger($1, endianness: .big) })
        + self.writeNFSOptional(attrs.uid, writer: { $0.writeInteger($1, endianness: .big) })
        + self.writeNFSOptional(attrs.gid, writer: { $0.writeInteger($1, endianness: .big) })
        + self.writeNFSOptional(attrs.size, writer: { $0.writeInteger($1, endianness: .big) })
        + self.writeNFSOptional(attrs.atime, writer: { $0.writeNFSTime($1) })
        + self.writeNFSOptional(attrs.mtime, writer: { $0.writeNFSTime($1) })
    }

    public mutating func readNFSCallSetattr() throws -> NFS3CallSetattr {
        let object = try self.readNFSFileHandle()
        let attributes = try self.readNFSCallSetattrAttributes()
        let `guard` = try self.readNFSOptional { try $0.readNFSTime() }

        return .init(object: object, newAttributes: attributes, guard: `guard`)
    }

    @discardableResult public mutating func writeNFSCallSetattr(_ call: NFS3CallSetattr) -> Int {
        return self.writeNFSFileHandle(call.object)
        + self.writeNFSCallSetattrAttributes(call.newAttributes)
        + self.writeNFSOptional(call.guard, writer: { $0.writeNFSTime($1) })
    }

    public mutating func readNFSReplySetattr() throws -> NFS3ReplySetattr {
        return NFS3ReplySetattr(
            result: try self.readNFSResult(
                readOkay: { buffer in
                    return NFS3ReplySetattr.Okay(wcc: try buffer.readNFSWeakCacheConsistencyData())
                },
                readFail: { buffer in
                    return NFS3ReplySetattr.Fail(wcc: try buffer.readNFSWeakCacheConsistencyData())
                }))
    }

    @discardableResult public mutating func writeNFSReplySetattr(_ reply: NFS3ReplySetattr) -> Int {
        var bytesWritten = self.writeNFSResultStatus(reply.result)

        switch reply.result {
        case .okay(let okay):
            bytesWritten += self.writeNFSWeakCacheConsistencyData(okay.wcc)
        case .fail(_, let fail):
            bytesWritten += self.writeNFSWeakCacheConsistencyData(fail.wcc)
        }
        return bytesWritten
    }
}
