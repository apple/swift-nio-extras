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

// MARK: - ReadDirPlus
public struct NFS3CallReadDirPlus: Hashable & Sendable {
    public init(
        fileHandle: NFS3FileHandle,
        cookie: NFS3Cookie,
        cookieVerifier: NFS3CookieVerifier,
        dirCount: NFS3Count,
        maxCount: NFS3Count
    ) {
        self.fileHandle = fileHandle
        self.cookie = cookie
        self.cookieVerifier = cookieVerifier
        self.dirCount = dirCount
        self.maxCount = maxCount
    }

    public var fileHandle: NFS3FileHandle
    public var cookie: NFS3Cookie
    public var cookieVerifier: NFS3CookieVerifier
    public var dirCount: NFS3Count
    public var maxCount: NFS3Count
}

public struct NFS3ReplyReadDirPlus: Hashable & Sendable {
    public init(result: NFS3Result<NFS3ReplyReadDirPlus.Okay, NFS3ReplyReadDirPlus.Fail>) {
        self.result = result
    }

    public struct Entry: Hashable & Sendable {
        public init(
            fileID: NFS3FileID,
            fileName: String,
            cookie: NFS3Cookie,
            nameAttributes: NFS3FileAttr? = nil,
            nameHandle: NFS3FileHandle? = nil
        ) {
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

    public struct Okay: Hashable & Sendable {
        public init(
            dirAttributes: NFS3FileAttr? = nil,
            cookieVerifier: NFS3CookieVerifier,
            entries: [NFS3ReplyReadDirPlus.Entry],
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
    public mutating func readNFS3CallReadDirPlus() throws -> NFS3CallReadDirPlus {
        let dir = try self.readNFS3FileHandle()
        let cookie = try self.readNFS3Cookie()
        let cookieVerifier = try self.readNFS3CookieVerifier()
        let dirCount = try self.readNFS3Count()
        let maxCount = try self.readNFS3Count()

        return NFS3CallReadDirPlus(
            fileHandle: dir,
            cookie: cookie,
            cookieVerifier: cookieVerifier,
            dirCount: dirCount,
            maxCount: maxCount
        )
    }

    @discardableResult public mutating func writeNFS3CallReadDirPlus(_ call: NFS3CallReadDirPlus) -> Int {
        self.writeNFS3FileHandle(call.fileHandle)
            + self.writeMultipleIntegers(
                call.cookie.rawValue,
                call.cookieVerifier.rawValue,
                call.dirCount.rawValue,
                call.maxCount.rawValue
            )
    }

    private mutating func readReadDirPlusEntry() throws -> NFS3ReplyReadDirPlus.Entry {
        let fileID = try self.readNFS3FileID()
        let fileName = try self.readNFS3String()
        let cookie = try self.readNFS3Cookie()
        let nameAttrs = try self.readNFS3Optional { try $0.readNFS3FileAttr() }
        let nameHandle = try self.readNFS3Optional { try $0.readNFS3FileHandle() }

        return NFS3ReplyReadDirPlus.Entry(
            fileID: fileID,
            fileName: fileName,
            cookie: cookie,
            nameAttributes: nameAttrs,
            nameHandle: nameHandle
        )
    }

    private mutating func writeReadDirPlusEntry(_ entry: NFS3ReplyReadDirPlus.Entry) -> Int {
        self.writeNFS3FileID(entry.fileID)
            + self.writeNFS3String(entry.fileName)
            + self.writeNFS3Cookie(entry.cookie)
            + self.writeNFS3Optional(entry.nameAttributes, writer: { $0.writeNFS3FileAttr($1) })
            + self.writeNFS3Optional(entry.nameHandle, writer: { $0.writeNFS3FileHandle($1) })
    }

    public mutating func readNFS3ReplyReadDirPlus() throws -> NFS3ReplyReadDirPlus {
        NFS3ReplyReadDirPlus(
            result: try self.readNFS3Result(
                readOkay: { buffer in
                    let attrs = try buffer.readNFS3Optional { try $0.readNFS3FileAttr() }
                    let cookieVerifier = try buffer.readNFS3CookieVerifier()

                    var entries: [NFS3ReplyReadDirPlus.Entry] = []
                    while let entry = try buffer.readNFS3Optional({ try $0.readReadDirPlusEntry() }) {
                        entries.append(entry)
                    }
                    let eof = try buffer.readNFS3Bool()

                    return NFS3ReplyReadDirPlus.Okay(
                        dirAttributes: attrs,
                        cookieVerifier: cookieVerifier,
                        entries: entries,
                        eof: eof
                    )
                },
                readFail: { buffer in
                    let attrs = try buffer.readNFS3Optional { try $0.readNFS3FileAttr() }

                    return NFS3ReplyReadDirPlus.Fail(dirAttributes: attrs)
                }
            )
        )
    }

    @discardableResult public mutating func writeNFS3ReplyReadDirPlus(_ rdp: NFS3ReplyReadDirPlus) -> Int {
        var bytesWritten = 0

        switch rdp.result {
        case .okay(let result):
            bytesWritten +=
                self.writeInteger(NFS3Status.ok.rawValue)
                + self.writeNFS3Optional(result.dirAttributes, writer: { $0.writeNFS3FileAttr($1) })
                + self.writeNFS3CookieVerifier(result.cookieVerifier)
            for entry in result.entries {
                bytesWritten +=
                    self.writeInteger(1, as: UInt32.self)
                    + self.writeReadDirPlusEntry(entry)
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
