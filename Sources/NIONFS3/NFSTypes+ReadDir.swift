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

// MARK: - ReadDir
public struct NFS3CallReadDir: Hashable & Sendable {
    public init(
        fileHandle: NFS3FileHandle,
        cookie: NFS3Cookie,
        cookieVerifier: NFS3CookieVerifier,
        maxResultByteCount: NFS3Count
    ) {
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

public struct NFS3ReplyReadDir: Hashable & Sendable {
    public init(result: NFS3Result<NFS3ReplyReadDir.Okay, NFS3ReplyReadDir.Fail>) {
        self.result = result
    }

    public struct Entry: Hashable & Sendable {
        public init(fileID: NFS3FileID, fileName: String, cookie: NFS3Cookie) {
            self.fileID = fileID
            self.fileName = fileName
            self.cookie = cookie
        }

        public var fileID: NFS3FileID
        public var fileName: String
        public var cookie: NFS3Cookie
    }

    public struct Okay: Hashable & Sendable {
        public init(
            dirAttributes: NFS3FileAttr? = nil,
            cookieVerifier: NFS3CookieVerifier,
            entries: [NFS3ReplyReadDir.Entry],
            eof: NFS3Bool
        ) {
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

    public struct Fail: Hashable & Sendable {
        public init(dirAttributes: NFS3FileAttr? = nil) {
            self.dirAttributes = dirAttributes
        }

        public var dirAttributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFS3CallReadDir() throws -> NFS3CallReadDir {
        let dir = try self.readNFS3FileHandle()
        let cookie = try self.readNFS3Cookie()
        let cookieVerifier = try self.readNFS3CookieVerifier()
        let maxResultByteCount = try self.readNFS3Count()

        return NFS3CallReadDir(
            fileHandle: dir,
            cookie: cookie,
            cookieVerifier: cookieVerifier,
            maxResultByteCount: maxResultByteCount
        )
    }

    @discardableResult public mutating func writeNFS3CallReadDir(_ call: NFS3CallReadDir) -> Int {
        self.writeNFS3FileHandle(call.fileHandle)
            + self.writeMultipleIntegers(
                call.cookie.rawValue,
                call.cookieVerifier.rawValue,
                call.maxResultByteCount.rawValue
            )
    }

    private mutating func readReadDirEntry() throws -> NFS3ReplyReadDir.Entry {
        let fileID = try self.readNFS3FileID()
        let fileName = try self.readNFS3String()
        let cookie = try self.readNFS3Cookie()

        return NFS3ReplyReadDir.Entry(
            fileID: fileID,
            fileName: fileName,
            cookie: cookie
        )
    }

    private mutating func writeReadDirEntry(_ entry: NFS3ReplyReadDir.Entry) -> Int {
        self.writeNFS3FileID(entry.fileID)
            + self.writeNFS3String(entry.fileName)
            + self.writeNFS3Cookie(entry.cookie)
    }

    public mutating func readNFS3ReplyReadDir() throws -> NFS3ReplyReadDir {
        NFS3ReplyReadDir(
            result: try self.readNFS3Result(
                readOkay: { buffer in
                    let dirAttributes = try buffer.readNFS3Optional { try $0.readNFS3FileAttr() }
                    let cookieVerifier = try buffer.readNFS3CookieVerifier()

                    var entries: [NFS3ReplyReadDir.Entry] = []
                    while let entry = try buffer.readNFS3Optional({ try $0.readReadDirEntry() }) {
                        entries.append(entry)
                    }
                    let eof = try buffer.readNFS3Bool()

                    return NFS3ReplyReadDir.Okay(
                        dirAttributes: dirAttributes,
                        cookieVerifier: cookieVerifier,
                        entries: entries,
                        eof: eof
                    )
                },
                readFail: { buffer in
                    let attrs = try buffer.readNFS3Optional { try $0.readNFS3FileAttr() }

                    return NFS3ReplyReadDir.Fail(dirAttributes: attrs)
                }
            )
        )
    }

    @discardableResult public mutating func writeNFS3ReplyReadDir(_ rd: NFS3ReplyReadDir) -> Int {
        var bytesWritten = 0
        switch rd.result {
        case .okay(let result):
            bytesWritten +=
                self.writeInteger(NFS3Status.ok.rawValue)
                + self.writeNFS3Optional(result.dirAttributes, writer: { $0.writeNFS3FileAttr($1) })
                + self.writeNFS3CookieVerifier(result.cookieVerifier)
            for entry in result.entries {
                bytesWritten +=
                    self.writeInteger(1, as: UInt32.self)
                    + self.writeReadDirEntry(entry)
            }
            bytesWritten +=
                self.writeInteger(0, as: UInt32.self)
                + self.writeInteger(result.eof == true ? 1 : 0, as: UInt32.self)
        case .fail(let status, let fail):
            precondition(status != .ok)
            bytesWritten +=
                self.writeInteger(status.rawValue)
                + self.writeNFS3Optional(fail.dirAttributes, writer: { $0.writeNFS3FileAttr($1) })
        }
        return bytesWritten
    }
}
