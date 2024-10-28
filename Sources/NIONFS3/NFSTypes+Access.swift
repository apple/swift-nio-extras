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

// MARK: - Access
public struct NFS3CallAccess: Hashable & Sendable {
    public init(object: NFS3FileHandle, access: NFS3Access) {
        self.object = object
        self.access = access
    }

    public var object: NFS3FileHandle
    public var access: NFS3Access
}

public struct NFS3ReplyAccess: Hashable & Sendable {
    public init(result: NFS3Result<NFS3ReplyAccess.Okay, NFS3ReplyAccess.Fail>) {
        self.result = result
    }

    public struct Okay: Hashable & Sendable {
        public init(dirAttributes: NFS3FileAttr?, access: NFS3Access) {
            self.dirAttributes = dirAttributes
            self.access = access
        }

        public var dirAttributes: NFS3FileAttr?
        public var access: NFS3Access
    }

    public struct Fail: Hashable & Sendable {
        public init(dirAttributes: NFS3FileAttr?) {
            self.dirAttributes = dirAttributes
        }

        public var dirAttributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFS3CallAccess() throws -> NFS3CallAccess {
        let fileHandle = try self.readNFS3FileHandle()
        let access = try self.readNFS3Access()
        return NFS3CallAccess(object: fileHandle, access: access)
    }

    @discardableResult public mutating func writeNFS3CallAccess(_ call: NFS3CallAccess) -> Int {
        self.writeNFS3FileHandle(call.object)
            + self.writeInteger(call.access.rawValue)
    }

    public mutating func readNFS3ReplyAccess() throws -> NFS3ReplyAccess {
        NFS3ReplyAccess(
            result: try self.readNFS3Result(
                readOkay: { buffer in
                    let attrs = try buffer.readNFS3Optional { buffer in
                        try buffer.readNFS3FileAttr()
                    }
                    let access = try buffer.readNFS3Access()
                    return NFS3ReplyAccess.Okay(dirAttributes: attrs, access: access)
                },
                readFail: { buffer in
                    NFS3ReplyAccess.Fail(
                        dirAttributes: try buffer.readNFS3Optional { buffer in
                            try buffer.readNFS3FileAttr()
                        }
                    )
                }
            )
        )
    }

    @discardableResult public mutating func writeNFS3ReplyAccess(_ accessResult: NFS3ReplyAccess) -> Int {
        var bytesWritten = 0

        switch accessResult.result {
        case .okay(let result):
            bytesWritten += self.writeInteger(NFS3Status.ok.rawValue)
            if let attrs = result.dirAttributes {
                bytesWritten +=
                    self.writeInteger(1, as: UInt32.self)
                    + self.writeNFS3FileAttr(attrs)
            } else {
                bytesWritten += self.writeInteger(0, as: UInt32.self)
            }
            bytesWritten += self.writeInteger(result.access.rawValue)
        case .fail(let status, let fail):
            precondition(status != .ok)
            bytesWritten += self.writeInteger(status.rawValue)
            if let attrs = fail.dirAttributes {
                bytesWritten +=
                    self.writeInteger(1, as: UInt32.self)
                    + self.writeNFS3FileAttr(attrs)
            } else {
                bytesWritten += self.writeInteger(0, as: UInt32.self)
            }
        }
        return bytesWritten
    }
}
