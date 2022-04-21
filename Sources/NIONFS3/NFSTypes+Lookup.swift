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

// MARK: - Lookup
public struct NFS3CallLookup: Equatable {
    public init(dir: NFS3FileHandle, name: String) {
        self.dir = dir
        self.name = name
    }

    public var dir: NFS3FileHandle
    public var name: String
}

public struct NFS3ReplyLookup: Equatable {
    public init(result: NFS3Result<NFS3ReplyLookup.Okay, NFS3ReplyLookup.Fail>) {
        self.result = result
    }

    public struct Okay: Equatable {
        public init(fileHandle: NFS3FileHandle, attributes: NFS3FileAttr?, dirAttributes: NFS3FileAttr?) {
            self.fileHandle = fileHandle
            self.attributes = attributes
            self.dirAttributes = dirAttributes
        }

        public var fileHandle: NFS3FileHandle
        public var attributes: NFS3FileAttr?
        public var dirAttributes: NFS3FileAttr?
    }

    public struct Fail: Equatable {
        public init(dirAttributes: NFS3FileAttr? = nil) {
            self.dirAttributes = dirAttributes
        }

        public var dirAttributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFSCallLookup() throws -> NFS3CallLookup {
        let dir = try self.readNFSFileHandle()
        let name = try self.readNFSString()
        return NFS3CallLookup(dir: dir, name: name)
    }

    public mutating func writeNFSCallLookup(_ call: NFS3CallLookup) {
        self.writeNFSFileHandle(call.dir)
        self.writeNFSString(call.name)
    }

    public mutating func readNFSReplyLookup() throws -> NFS3ReplyLookup {
        return NFS3ReplyLookup(
            result: try self.readNFSResult(
                readOkay: { buffer in
                    let fileHandle = try buffer.readNFSFileHandle()
                    let attrs = try buffer.readNFSOptional { buffer in
                        try buffer.readNFSFileAttr()
                    }
                    let dirAttrs = try buffer.readNFSOptional { buffer in
                        try buffer.readNFSFileAttr()
                    }

                    return NFS3ReplyLookup.Okay(fileHandle: fileHandle, attributes: attrs, dirAttributes: dirAttrs)
                },
                readFail: { buffer in
                    let attrs = try buffer.readNFSOptional { buffer in
                        try buffer.readNFSFileAttr()
                    }
                    return NFS3ReplyLookup.Fail(dirAttributes: attrs)
                })
        )
    }

    public mutating func writeNFSReplyLookup(_ lookupResult: NFS3ReplyLookup) {
        switch lookupResult.result {
        case .okay(let result):
            self.writeInteger(NFS3Status.ok.rawValue, endianness: .big)
            self.writeNFSFileHandle(result.fileHandle)
            if let attrs = result.attributes {
                self.writeInteger(1, endianness: .big, as: UInt32.self)
                self.writeNFSFileAttr(attrs)
            } else {
                self.writeInteger(0, endianness: .big, as: UInt32.self)
            }
            if let attrs = result.dirAttributes {
                self.writeInteger(1, endianness: .big, as: UInt32.self)
                self.writeNFSFileAttr(attrs)
            } else {
                self.writeInteger(0, endianness: .big, as: UInt32.self)
            }
        case .fail(let status, let fail):
            precondition(status != .ok)
            self.writeInteger(status.rawValue, endianness: .big)
            if let attrs = fail.dirAttributes {
                self.writeInteger(1, endianness: .big, as: UInt32.self)
                self.writeNFSFileAttr(attrs)
            } else {
                self.writeInteger(0, endianness: .big, as: UInt32.self)
            }
        }
    }
}
