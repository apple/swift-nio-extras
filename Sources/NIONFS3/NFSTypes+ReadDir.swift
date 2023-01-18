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

// MARK: - ReadDir
public struct NFS3CallReadDir: Hashable {
    public init(fileHandle: NFS3FileHandle, cookie: NFS3Cookie, cookieVerifier: NFS3CookieVerifier, maxResultByteCount: UInt32) {
        self.fileHandle = fileHandle
        self.cookie = cookie
        self.cookieVerifier = cookieVerifier
        self.maxResultByteCount = maxResultByteCount
    }

    public var fileHandle: NFS3FileHandle
    public var cookie: NFS3Cookie
    public var cookieVerifier: NFS3CookieVerifier
    public var maxResultByteCount: NFS3Count
}

public struct NFS3ReplyReadDir: Hashable {
    public init(result: NFS3Result<NFS3ReplyReadDir.Okay, NFS3ReplyReadDir.Fail>) {
        self.result = result
    }

    public struct Entry: Hashable {
        public init(fileID: NFS3FileID, fileName: String, cookie: NFS3Cookie) {
            self.fileID = fileID
            self.fileName = fileName
            self.cookie = cookie
        }

        public var fileID: NFS3FileID
        public var fileName: String
        public var cookie: NFS3Cookie
    }

    public struct Okay: Hashable {
        public init(dirAttributes: NFS3FileAttr? = nil, cookieVerifier: NFS3CookieVerifier, entries: [NFS3ReplyReadDir.Entry], eof: NFS3Bool) {
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
    public mutating func readNFSCallReadDir() throws -> NFS3CallReadDir {
        let dir = try self.readNFSFileHandle()
        let cookie = try self.readNFSInteger(as: NFS3Cookie.self)
        let cookieVerifier = try self.readNFSInteger(as: NFS3CookieVerifier.self)
        let maxResultByteCount = try self.readNFSInteger(as: NFS3Count.self)

        return NFS3CallReadDir(fileHandle: dir,
                               cookie: cookie,
                               cookieVerifier: cookieVerifier,
                               maxResultByteCount: maxResultByteCount)
    }

    @discardableResult public mutating func writeNFSCallReadDir(_ call: NFS3CallReadDir) -> Int {
        return self.writeNFSFileHandle(call.fileHandle)
        + self.writeMultipleIntegers(
            call.cookie,
            call.cookieVerifier,
            call.maxResultByteCount
        )
    }

    private mutating func readReadDirEntry() throws -> NFS3ReplyReadDir.Entry {
        let fileID = try self.readNFSInteger(as: NFS3FileID.self)
        let fileName = try self.readNFSString()
        let cookie = try self.readNFSInteger(as: NFS3Cookie.self)

        return NFS3ReplyReadDir.Entry(fileID: fileID,
                                      fileName: fileName,
                                      cookie: cookie)
    }

    private mutating func writeReadDirEntry(_ entry: NFS3ReplyReadDir.Entry) -> Int {
        return self.writeNFSFileID(entry.fileID)
        + self.writeNFSString(entry.fileName)
        + self.writeNFSCookie(entry.cookie)
    }

    public mutating func readNFSReplyReadDir() throws -> NFS3ReplyReadDir {
        return NFS3ReplyReadDir(
            result: try self.readNFSResult(
                readOkay: { buffer in
                    let dirAttributes = try buffer.readNFSOptional { try $0.readNFSFileAttr() }
                    let cookieVerifier = try buffer.readNFSInteger(as: NFS3CookieVerifier.self)

                    var entries: [NFS3ReplyReadDir.Entry] = []
                    while let entry = try buffer.readNFSOptional({ try $0.readReadDirEntry() }) {
                        entries.append(entry)
                    }
                    let eof = try buffer.readNFSBool()

                    return NFS3ReplyReadDir.Okay(dirAttributes: dirAttributes,
                                                 cookieVerifier: cookieVerifier,
                                                 entries: entries,
                                                 eof: eof)
                },
                readFail: { buffer in
                    let attrs = try buffer.readNFSOptional { try $0.readNFSFileAttr() }

                    return NFS3ReplyReadDir.Fail(dirAttributes: attrs)
                })
        )
    }

    @discardableResult public mutating func writeNFSReplyReadDir(_ rd: NFS3ReplyReadDir) -> Int {
        var bytesWritten = 0
        switch rd.result {
        case .okay(let result):
            bytesWritten += self.writeInteger(NFS3Status.ok.rawValue, endianness: .big)
            + self.writeNFSOptional(result.dirAttributes, writer: { $0.writeNFSFileAttr($1) })
            + self.writeNFSCookieVerifier(result.cookieVerifier)
            for entry in result.entries {
                bytesWritten += self.writeInteger(1, endianness: .big, as: UInt32.self)
                + self.writeReadDirEntry(entry)
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
