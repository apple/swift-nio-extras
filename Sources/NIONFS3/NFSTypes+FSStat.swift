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

// MARK: - FSStat
public struct NFS3CallFSStat: Hashable & Sendable {
    public init(fsroot: NFS3FileHandle) {
        self.fsroot = fsroot
    }

    public var fsroot: NFS3FileHandle
}

public struct NFS3ReplyFSStat: Hashable & Sendable {
    public init(result: NFS3Result<NFS3ReplyFSStat.Okay, NFS3ReplyFSStat.Fail>) {
        self.result = result
    }

    public struct Okay: Hashable & Sendable {
        public init(
            attributes: NFS3FileAttr?,
            tbytes: NFS3Size,
            fbytes: NFS3Size,
            abytes: NFS3Size,
            tfiles: NFS3Size,
            ffiles: NFS3Size,
            afiles: NFS3Size,
            invarsec: UInt32
        ) {
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

    public struct Fail: Hashable & Sendable {
        public init(attributes: NFS3FileAttr?) {
            self.attributes = attributes
        }

        public var attributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFS3CallFSStat() throws -> NFS3CallFSStat {
        let fileHandle = try self.readNFS3FileHandle()
        return NFS3CallFSStat(fsroot: fileHandle)
    }

    @discardableResult public mutating func writeNFS3CallFSStat(_ call: NFS3CallFSStat) -> Int {
        self.writeNFS3FileHandle(call.fsroot)
    }

    private mutating func readNFS3ReplyFSStatOkay() throws -> NFS3ReplyFSStat.Okay {
        let attrs = try self.readNFS3Optional { buffer in
            try buffer.readNFS3FileAttr()
        }
        if let values = self.readMultipleIntegers(as: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt32).self) {
            return .init(
                attributes: attrs,
                tbytes: NFS3Size(rawValue: values.0),
                fbytes: NFS3Size(rawValue: values.1),
                abytes: NFS3Size(rawValue: values.2),
                tfiles: NFS3Size(rawValue: values.3),
                ffiles: NFS3Size(rawValue: values.4),
                afiles: NFS3Size(rawValue: values.5),
                invarsec: values.6
            )
        } else {
            throw NFS3Error.illegalRPCTooShort
        }
    }

    public mutating func readNFS3ReplyFSStat() throws -> NFS3ReplyFSStat {
        NFS3ReplyFSStat(
            result: try self.readNFS3Result(
                readOkay: { buffer in
                    try buffer.readNFS3ReplyFSStatOkay()
                },
                readFail: { buffer in
                    NFS3ReplyFSStat.Fail(
                        attributes: try buffer.readNFS3Optional { buffer in
                            try buffer.readNFS3FileAttr()
                        }
                    )
                }
            )
        )
    }

    @discardableResult public mutating func writeNFS3ReplyFSStat(_ reply: NFS3ReplyFSStat) -> Int {
        var bytesWritten = self.writeNFS3ResultStatus(reply.result)

        switch reply.result {
        case .okay(let okay):
            bytesWritten +=
                self.writeNFS3Optional(okay.attributes, writer: { $0.writeNFS3FileAttr($1) })
                + self.writeMultipleIntegers(
                    okay.tbytes.rawValue,
                    okay.fbytes.rawValue,
                    okay.abytes.rawValue,
                    okay.tfiles.rawValue,
                    okay.ffiles.rawValue,
                    okay.afiles.rawValue,
                    okay.invarsec
                )
        case .fail(_, let fail):
            bytesWritten += self.writeNFS3Optional(fail.attributes, writer: { $0.writeNFS3FileAttr($1) })
        }
        return bytesWritten
    }
}
