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

// MARK: - PathConf
public struct NFS3CallPathConf: Equatable {
    public init(object: NFS3FileHandle) {
        self.object = object
    }

    public var object: NFS3FileHandle
}

public struct NFS3ReplyPathConf: Equatable {
    public init(result: NFS3Result<NFS3ReplyPathConf.Okay, NFS3ReplyPathConf.Fail>) {
        self.result = result
    }

    public struct Okay: Equatable {
        public init(attributes: NFS3FileAttr?, linkMax: UInt32, nameMax: UInt32, noTrunc: NFS3Bool, chownRestricted: NFS3Bool, caseInsensitive: NFS3Bool, casePreserving: NFS3Bool) {
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

    public struct Fail: Equatable {
        public init(attributes: NFS3FileAttr?) {
            self.attributes = attributes
        }

        public var attributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFSCallPathConf() throws -> NFS3CallPathConf {
        let fileHandle = try self.readNFSFileHandle()
        return NFS3CallPathConf(object: fileHandle)
    }

    public mutating func writeNFSCallPathConf(_ call: NFS3CallPathConf) {
        self.writeNFSFileHandle(call.object)
    }

    public mutating func readNFSReplyPathConf() throws -> NFS3ReplyPathConf {
        return NFS3ReplyPathConf(
            result: try self.readNFSResult(
                readOkay: { buffer in
                    let attrs = try buffer.readNFSOptional { buffer in
                        try buffer.readNFSFileAttr()
                    }
                    guard let values = buffer.readMultipleIntegers(as: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32).self) else {
                        throw NFS3Error.illegalRPCTooShort
                    }

                    return NFS3ReplyPathConf.Okay(attributes: attrs,
                                                 linkMax: values.0,
                                                 nameMax: values.1,
                                                 noTrunc: values.2 == 0 ? false : true,
                                                 chownRestricted: values.3 == 0 ? false : true,
                                                 caseInsensitive: values.4 == 0 ? false : true,
                                                 casePreserving: values.5 == 0 ? false : true)
                },
                readFail: { buffer in
                    let attrs = try buffer.readNFSOptional { buffer in
                        try buffer.readNFSFileAttr()
                    }
                    return NFS3ReplyPathConf.Fail(attributes: attrs)
                })
        )
    }

    public mutating func writeNFSReplyPathConf(_ pathconf: NFS3ReplyPathConf) {
        self.writeNFSResultStatus(pathconf.result)

        switch pathconf.result {
        case .okay(let pathconf):
            self.writeNFSOptional(pathconf.attributes, writer: { $0.writeNFSFileAttr($1) })
            self.writeMultipleIntegers(
                pathconf.linkMax,
                pathconf.nameMax,
                pathconf.noTrunc ? UInt32(1) : 0,
                pathconf.chownRestricted ? UInt32(1) : 0,
                pathconf.caseInsensitive ? UInt32(1) : 0,
                pathconf.casePreserving ? UInt32(1) : 0
            )
        case .fail(_, let fail):
            self.writeNFSOptional(fail.attributes, writer: { $0.writeNFSFileAttr($1) })
        }
    }
}
