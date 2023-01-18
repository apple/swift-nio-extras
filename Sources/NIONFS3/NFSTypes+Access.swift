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

// MARK: - Access
public struct NFS3CallAccess: Hashable {
    public init(object: NFS3FileHandle, access: NFS3Access) {
        self.object = object
        self.access = access
    }

    public var object: NFS3FileHandle
    public var access: NFS3Access
}

public struct NFS3ReplyAccess: Hashable {
    public init(result: NFS3Result<NFS3ReplyAccess.Okay, NFS3ReplyAccess.Fail>) {
        self.result = result
    }

    public struct Okay: Hashable {
        public init(dirAttributes: NFS3FileAttr?, access: NFS3Access) {
            self.dirAttributes = dirAttributes
            self.access = access
        }

        public var dirAttributes: NFS3FileAttr?
        public var access: NFS3Access
    }

    public struct Fail: Hashable {
        public init(dirAttributes: NFS3FileAttr?) {
            self.dirAttributes = dirAttributes
        }

        public var dirAttributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFSCallAccess() throws -> NFS3CallAccess {
        let fileHandle = try self.readNFSFileHandle()
        let access = try self.readNFSInteger(as: UInt32.self)
        return NFS3CallAccess(object: fileHandle, access: .init(rawValue: access))
    }

    @discardableResult public mutating func writeNFSCallAccess(_ call: NFS3CallAccess) -> Int {
        return self.writeNFSFileHandle(call.object)
        + self.writeInteger(call.access.rawValue, endianness: .big)
    }

    public mutating func readNFSReplyAccess() throws -> NFS3ReplyAccess {
        return NFS3ReplyAccess(result: try self.readNFSResult(
            readOkay: { buffer in
                let attrs = try buffer.readNFSOptional { buffer in
                    try buffer.readNFSFileAttr()
                }
                let rawValue = try buffer.readNFSInteger(as: UInt32.self)
                return NFS3ReplyAccess.Okay(dirAttributes: attrs, access: NFS3Access(rawValue: rawValue))
            },
            readFail: { buffer in
                return NFS3ReplyAccess.Fail(dirAttributes: try buffer.readNFSOptional { buffer in
                    try buffer.readNFSFileAttr()
                })
            }))
    }

    @discardableResult public mutating func writeNFSReplyAccess(_ accessResult: NFS3ReplyAccess) -> Int {
        var bytesWritten = 0

        switch accessResult.result {
        case .okay(let result):
            bytesWritten += self.writeInteger(NFS3Status.ok.rawValue, endianness: .big)
            if let attrs = result.dirAttributes {
                bytesWritten += self.writeInteger(1, endianness: .big, as: UInt32.self)
                + self.writeNFSFileAttr(attrs)
            } else {
                bytesWritten += self.writeInteger(0, endianness: .big, as: UInt32.self)
            }
            bytesWritten += self.writeInteger(result.access.rawValue, endianness: .big)
        case .fail(let status, let fail):
            precondition(status != .ok)
            bytesWritten += self.writeInteger(status.rawValue, endianness: .big)
            if let attrs = fail.dirAttributes {
                bytesWritten += self.writeInteger(1, endianness: .big, as: UInt32.self)
                + self.writeNFSFileAttr(attrs)
            } else {
                bytesWritten += self.writeInteger(0, endianness: .big, as: UInt32.self)
            }
        }
        return bytesWritten
    }
}
