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

// MARK: - FSStat
public struct NFS3CallFSStat: Hashable {
    public init(fsroot: NFS3FileHandle) {
        self.fsroot = fsroot
    }

    public var fsroot: NFS3FileHandle
}

public struct NFS3ReplyFSStat: Hashable {
    public init(result: NFS3Result<NFS3ReplyFSStat.Okay, NFS3ReplyFSStat.Fail>) {
        self.result = result
    }

    public struct Okay: Hashable {
        public init(attributes: NFS3FileAttr?,
                    tbytes: NFS3Size, fbytes: NFS3Size, abytes: NFS3Size,
                    tfiles: NFS3Size, ffiles: NFS3Size, afiles: NFS3Size,
                    invarsec: UInt32) {
            self.attributes = attributes
            self.tbytes = tbytes
            self.fbytes = fbytes
            self.abytes = abytes
            self.tfiles = tfiles
            self.ffiles = ffiles
            self.afiles = afiles
            self.invarsec = invarsec
        }

        public var attributes: NFS3FileAttr?
        public var tbytes: NFS3Size
        public var fbytes: NFS3Size
        public var abytes: NFS3Size
        public var tfiles: NFS3Size
        public var ffiles: NFS3Size
        public var afiles: NFS3Size
        public var invarsec: UInt32
    }

    public struct Fail: Hashable {
        public init(attributes: NFS3FileAttr?) {
            self.attributes = attributes
        }

        public var attributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFSCallFSStat() throws -> NFS3CallFSStat {
        let fileHandle = try self.readNFSFileHandle()
        return NFS3CallFSStat(fsroot: fileHandle)
    }

    @discardableResult public mutating func writeNFSCallFSStat(_ call: NFS3CallFSStat) -> Int {
        self.writeNFSFileHandle(call.fsroot)
    }

    private mutating func readNFSReplyFSStatOkay() throws -> NFS3ReplyFSStat.Okay {
        let attrs = try self.readNFSOptional { buffer in
            try buffer.readNFSFileAttr()
        }
        if let values = self.readMultipleIntegers(as: (NFS3Size, NFS3Size, NFS3Size, NFS3Size, NFS3Size, NFS3Size, UInt32).self) {
            return .init(attributes: attrs,
                         tbytes: values.0, fbytes: values.1, abytes: values.2,
                         tfiles: values.3, ffiles: values.4, afiles: values.5,
                         invarsec: values.6)
        } else {
            throw NFS3Error.illegalRPCTooShort
        }
    }

    public mutating func readNFSReplyFSStat() throws -> NFS3ReplyFSStat {
        return NFS3ReplyFSStat(
            result: try self.readNFSResult(
                readOkay: { buffer in
                    try buffer.readNFSReplyFSStatOkay()
                },
                readFail: { buffer in
                    NFS3ReplyFSStat.Fail(
                        attributes: try buffer.readNFSOptional { buffer in
                            try buffer.readNFSFileAttr()
                        }
                    )
                })
        )
    }

    @discardableResult public mutating func writeNFSReplyFSStat(_ reply: NFS3ReplyFSStat) -> Int {
        var bytesWritten = self.writeNFSResultStatus(reply.result)

        switch reply.result {
        case .okay(let okay):
            bytesWritten += self.writeNFSOptional(okay.attributes, writer: { $0.writeNFSFileAttr($1) })
            + self.writeMultipleIntegers(
                okay.tbytes,
                okay.fbytes,
                okay.abytes,
                okay.tfiles,
                okay.ffiles,
                okay.afiles,
                okay.invarsec,
                endianness: .big)
        case .fail(_, let fail):
            bytesWritten += self.writeNFSOptional(fail.attributes, writer: { $0.writeNFSFileAttr($1) })
        }
        return bytesWritten
    }
}
