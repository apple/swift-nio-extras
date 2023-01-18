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

// MARK: - ReadDirPlus
public struct NFS3CallReadDirPlus: Hashable {
    public init(fileHandle: NFS3FileHandle, cookie: NFS3Cookie, cookieVerifier: NFS3CookieVerifier, dirCount: UInt32, maxCount: UInt32) {
        self.fileHandle = fileHandle
        self.cookie = cookie
        self.cookieVerifier = cookieVerifier
        self.dirCount = dirCount
        self.maxCount = maxCount
    }

    public var fileHandle: NFS3FileHandle
    public var cookie: NFS3Cookie
    public var cookieVerifier: NFS3CookieVerifier
    public var dirCount: UInt32
    public var maxCount: UInt32
}

public struct NFS3ReplyReadDirPlus: Hashable {
    public init(result: NFS3Result<NFS3ReplyReadDirPlus.Okay, NFS3ReplyReadDirPlus.Fail>) {
        self.result = result
    }

    public struct Entry: Hashable {
        public init(fileID: NFS3FileID, fileName: String, cookie: NFS3Cookie, nameAttributes: NFS3FileAttr? = nil, nameHandle: NFS3FileHandle? = nil) {
            self.fileID = fileID
            self.fileName = fileName
            self.cookie = cookie
            self.nameAttributes = nameAttributes
            self.nameHandle = nameHandle
        }

        public var fileID: NFS3FileID
        public var fileName: String
        public var cookie: NFS3Cookie
        public var nameAttributes: NFS3FileAttr?
        public var nameHandle: NFS3FileHandle?
    }

    public struct Okay: Hashable {
        public init(dirAttributes: NFS3FileAttr? = nil, cookieVerifier: NFS3CookieVerifier, entries: [NFS3ReplyReadDirPlus.Entry], eof: NFS3Bool) {
            self.dirAttributes = dirAttributes
            self.cookieVerifier = cookieVerifier
            self.entries = entries
            self.eof = eof
        }

        public var dirAttributes: NFS3FileAttr?
        public var cookieVerifier: NFS3CookieVerifier
        public var entries: [Entry]
        public var eof: NFS3Bool
    }

    public struct Fail: Hashable {
        public init(dirAttributes: NFS3FileAttr? = nil) {
            self.dirAttributes = dirAttributes
        }

        public var dirAttributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFSCallReadDirPlus() throws -> NFS3CallReadDirPlus {
        let dir = try self.readNFSFileHandle()
        let cookie = try self.readNFSInteger(as: UInt64.self)
        let cookieVerifier = try self.readNFSInteger(as: UInt64.self)
        let dirCount = try self.readNFSInteger(as: UInt32.self)
        let maxCount = try self.readNFSInteger(as: UInt32.self)

        return NFS3CallReadDirPlus(fileHandle: dir,
                                  cookie: cookie,
                                  cookieVerifier: cookieVerifier,
                                  dirCount: dirCount,
                                  maxCount: maxCount)
    }

    @discardableResult public mutating func writeNFSCallReadDirPlus(_ call: NFS3CallReadDirPlus) -> Int {
        return self.writeNFSFileHandle(call.fileHandle)
        + self.writeMultipleIntegers(
            call.cookie,
            call.cookieVerifier,
            call.dirCount,
            call.maxCount
        )
    }

    private mutating func readReadDirPlusEntry() throws -> NFS3ReplyReadDirPlus.Entry {
        let fileID = try self.readNFSInteger(as: NFS3FileID.self)
        let fileName = try self.readNFSString()
        let cookie = try self.readNFSInteger(as: NFS3Cookie.self)
        let nameAttrs = try self.readNFSOptional { try $0.readNFSFileAttr() }
        let nameHandle = try self.readNFSOptional { try $0.readNFSFileHandle() }

        return NFS3ReplyReadDirPlus.Entry(fileID: fileID,
                                         fileName: fileName,
                                         cookie: cookie,
                                         nameAttributes: nameAttrs,
                                         nameHandle: nameHandle)
    }

    private mutating func writeReadDirPlusEntry(_ entry: NFS3ReplyReadDirPlus.Entry) -> Int {
        return self.writeNFSFileID(entry.fileID)
        + self.writeNFSString(entry.fileName)
        + self.writeNFSCookie(entry.cookie)
        + self.writeNFSOptional(entry.nameAttributes, writer: { $0.writeNFSFileAttr($1) })
        + self.writeNFSOptional(entry.nameHandle, writer: { $0.writeNFSFileHandle($1) })
    }

    public mutating func readNFSReplyReadDirPlus() throws -> NFS3ReplyReadDirPlus {
        return NFS3ReplyReadDirPlus(
            result: try self.readNFSResult(
                readOkay: { buffer in
                    let attrs = try buffer.readNFSOptional { try $0.readNFSFileAttr() }
                    let cookieVerifier = try buffer.readNFSInteger(as: NFS3CookieVerifier.self)

                    var entries: [NFS3ReplyReadDirPlus.Entry] = []
                    while let entry = try buffer.readNFSOptional({ try $0.readReadDirPlusEntry() }) {
                        entries.append(entry)
                    }
                    let eof = try buffer.readNFSBool()

                    return NFS3ReplyReadDirPlus.Okay(dirAttributes: attrs,
                                                    cookieVerifier: cookieVerifier,
                                                    entries: entries,
                                                    eof: eof)
                },
                readFail: { buffer in
                    let attrs = try buffer.readNFSOptional { try $0.readNFSFileAttr() }

                    return NFS3ReplyReadDirPlus.Fail(dirAttributes: attrs)
                })
        )
    }

    @discardableResult public mutating func writeNFSReplyReadDirPlus(_ rdp: NFS3ReplyReadDirPlus) -> Int {
        var bytesWritten = 0

        switch rdp.result {
        case .okay(let result):
            bytesWritten += self.writeInteger(NFS3Status.ok.rawValue, endianness: .big)
            + self.writeNFSOptional(result.dirAttributes, writer: { $0.writeNFSFileAttr($1) })
            + self.writeNFSCookieVerifier(result.cookieVerifier)
            for entry in result.entries {
                bytesWritten += self.writeInteger(1, endianness: .big, as: UInt32.self)
                + self.writeReadDirPlusEntry(entry)
            }
            bytesWritten += self.writeInteger(0, endianness: .big, as: UInt32.self)
            + self.writeInteger(result.eof == true ? 1 : 0, endianness: .big, as: UInt32.self)
        case .fail(let status, let fail):
            precondition(status != .ok)
            bytesWritten += self.writeInteger(status.rawValue, endianness: .big)
            + self.writeNFSOptional(fail.dirAttributes, writer: { $0.writeNFSFileAttr($1) })
        }

        return bytesWritten
    }
}
