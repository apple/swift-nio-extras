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

// MARK: - PathConf
public struct NFS3CallPathConf: Hashable & Sendable {
    public init(object: NFS3FileHandle) {
        self.object = object
    }

    public var object: NFS3FileHandle
}

public struct NFS3ReplyPathConf: Hashable & Sendable {
    public init(result: NFS3Result<NFS3ReplyPathConf.Okay, NFS3ReplyPathConf.Fail>) {
        self.result = result
    }

    public struct Okay: Hashable & Sendable {
        public init(
            attributes: NFS3FileAttr?,
            linkMax: UInt32,
            nameMax: UInt32,
            noTrunc: NFS3Bool,
            chownRestricted: NFS3Bool,
            caseInsensitive: NFS3Bool,
            casePreserving: NFS3Bool
        ) {
            self.attributes = attributes
            self.linkMax = linkMax
            self.nameMax = nameMax
            self.noTrunc = noTrunc
            self.chownRestricted = chownRestricted
            self.caseInsensitive = caseInsensitive
            self.casePreserving = casePreserving
        }

        public var attributes: NFS3FileAttr?
        public var linkMax: UInt32
        public var nameMax: UInt32
        public var noTrunc: NFS3Bool
        public var chownRestricted: NFS3Bool
        public var caseInsensitive: NFS3Bool
        public var casePreserving: NFS3Bool
    }

    public struct Fail: Hashable & Sendable {
        public init(attributes: NFS3FileAttr?) {
            self.attributes = attributes
        }

        public var attributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFS3CallPathConf() throws -> NFS3CallPathConf {
        let fileHandle = try self.readNFS3FileHandle()
        return NFS3CallPathConf(object: fileHandle)
    }

    @discardableResult public mutating func writeNFS3CallPathConf(_ call: NFS3CallPathConf) -> Int {
        self.writeNFS3FileHandle(call.object)
    }

    public mutating func readNFS3ReplyPathConf() throws -> NFS3ReplyPathConf {
        NFS3ReplyPathConf(
            result: try self.readNFS3Result(
                readOkay: { buffer in
                    let attrs = try buffer.readNFS3Optional { buffer in
                        try buffer.readNFS3FileAttr()
                    }
                    guard
                        let values = buffer.readMultipleIntegers(
                            as: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32).self
                        )
                    else {
                        throw NFS3Error.illegalRPCTooShort
                    }

                    return NFS3ReplyPathConf.Okay(
                        attributes: attrs,
                        linkMax: values.0,
                        nameMax: values.1,
                        noTrunc: values.2 == 0 ? false : true,
                        chownRestricted: values.3 == 0 ? false : true,
                        caseInsensitive: values.4 == 0 ? false : true,
                        casePreserving: values.5 == 0 ? false : true
                    )
                },
                readFail: { buffer in
                    let attrs = try buffer.readNFS3Optional { buffer in
                        try buffer.readNFS3FileAttr()
                    }
                    return NFS3ReplyPathConf.Fail(attributes: attrs)
                }
            )
        )
    }

    @discardableResult public mutating func writeNFS3ReplyPathConf(_ pathconf: NFS3ReplyPathConf) -> Int {
        var bytesWritten = self.writeNFS3ResultStatus(pathconf.result)

        switch pathconf.result {
        case .okay(let pathconf):
            bytesWritten +=
                self.writeNFS3Optional(pathconf.attributes, writer: { $0.writeNFS3FileAttr($1) })
                + self.writeMultipleIntegers(
                    pathconf.linkMax,
                    pathconf.nameMax,
                    pathconf.noTrunc ? UInt32(1) : 0,
                    pathconf.chownRestricted ? UInt32(1) : 0,
                    pathconf.caseInsensitive ? UInt32(1) : 0,
                    pathconf.casePreserving ? UInt32(1) : 0
                )
        case .fail(_, let fail):
            bytesWritten += self.writeNFS3Optional(fail.attributes, writer: { $0.writeNFS3FileAttr($1) })
        }
        return bytesWritten
    }
}
