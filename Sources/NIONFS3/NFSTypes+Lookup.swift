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

// MARK: - Lookup
public struct NFS3CallLookup: Hashable & Sendable {
    public init(dir: NFS3FileHandle, name: String) {
        self.dir = dir
        self.name = name
    }

    public var dir: NFS3FileHandle
    public var name: String
}

public struct NFS3ReplyLookup: Hashable & Sendable {
    public init(result: NFS3Result<NFS3ReplyLookup.Okay, NFS3ReplyLookup.Fail>) {
        self.result = result
    }

    public struct Okay: Hashable & Sendable {
        public init(fileHandle: NFS3FileHandle, attributes: NFS3FileAttr?, dirAttributes: NFS3FileAttr?) {
            self.fileHandle = fileHandle
            self.attributes = attributes
            self.dirAttributes = dirAttributes
        }

        public var fileHandle: NFS3FileHandle
        public var attributes: NFS3FileAttr?
        public var dirAttributes: NFS3FileAttr?
    }

    public struct Fail: Hashable & Sendable {
        public init(dirAttributes: NFS3FileAttr? = nil) {
            self.dirAttributes = dirAttributes
        }

        public var dirAttributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFS3CallLookup() throws -> NFS3CallLookup {
        let dir = try self.readNFS3FileHandle()
        let name = try self.readNFS3String()
        return NFS3CallLookup(dir: dir, name: name)
    }

    @discardableResult public mutating func writeNFS3CallLookup(_ call: NFS3CallLookup) -> Int {
        self.writeNFS3FileHandle(call.dir)
            + self.writeNFS3String(call.name)
    }

    public mutating func readNFS3ReplyLookup() throws -> NFS3ReplyLookup {
        NFS3ReplyLookup(
            result: try self.readNFS3Result(
                readOkay: { buffer in
                    let fileHandle = try buffer.readNFS3FileHandle()
                    let attrs = try buffer.readNFS3Optional { buffer in
                        try buffer.readNFS3FileAttr()
                    }
                    let dirAttrs = try buffer.readNFS3Optional { buffer in
                        try buffer.readNFS3FileAttr()
                    }

                    return NFS3ReplyLookup.Okay(fileHandle: fileHandle, attributes: attrs, dirAttributes: dirAttrs)
                },
                readFail: { buffer in
                    let attrs = try buffer.readNFS3Optional { buffer in
                        try buffer.readNFS3FileAttr()
                    }
                    return NFS3ReplyLookup.Fail(dirAttributes: attrs)
                }
            )
        )
    }

    @discardableResult public mutating func writeNFS3ReplyLookup(_ lookupResult: NFS3ReplyLookup) -> Int {
        var bytesWritten = 0

        switch lookupResult.result {
        case .okay(let result):
            bytesWritten +=
                self.writeInteger(NFS3Status.ok.rawValue)
                + self.writeNFS3FileHandle(result.fileHandle)
            if let attrs = result.attributes {
                bytesWritten +=
                    self.writeInteger(1, as: UInt32.self)
                    + self.writeNFS3FileAttr(attrs)
            } else {
                bytesWritten += self.writeInteger(0, as: UInt32.self)
            }
            if let attrs = result.dirAttributes {
                bytesWritten +=
                    self.writeInteger(1, as: UInt32.self)
                    + self.writeNFS3FileAttr(attrs)
            } else {
                bytesWritten += self.writeInteger(0, as: UInt32.self)
            }
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
