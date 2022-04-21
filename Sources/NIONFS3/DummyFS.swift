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

final class DummyFS: NFS3FileSystemNoAuth {
    struct ChildEntry {
        var name: String
        var index: Int
    }

    struct InodeEntry {
        var type: NFS3FileType
        var children: [ChildEntry]
    }

    private var files: [InodeEntry] = []
    private var root: Int = 7
    private let fileContent: ByteBuffer = {
        var buffer = ByteBuffer(repeating: UInt8(ascii: "A"), count: 1 * 1024 * 1024)
        buffer.setInteger(UInt8(ascii: "H"), at: 0)
        buffer.setInteger(UInt8(ascii: "L"), at: buffer.writerIndex - 2)
        buffer.setInteger(UInt8(ascii: "L"), at: buffer.writerIndex - 3)
        buffer.setInteger(UInt8(ascii: "O"), at: buffer.writerIndex - 1)
        return buffer
    }()

    init() {
        // 0 doesn't exist?
        self.files.append(.init(type: .regular, children: []))

        let idDirFileA = self.files.count
        self.files.append(.init(type: .regular, children: []))

        let idDirFileB = self.files.count
        self.files.append(.init(type: .regular, children: []))

        let idDirFileC = self.files.count
        self.files.append(.init(type: .regular, children: []))

        let idDirFileD = self.files.count
        self.files.append(.init(type: .regular, children: []))

        let idDirFileE = self.files.count
        self.files.append(.init(type: .regular, children: []))

        let idDirFileF = self.files.count
        self.files.append(.init(type: .regular, children: []))

        let idDir = self.files.count
        self.files.append(.init(type: .directory,
                                children: [
                                    .init(name: ".", index: idDir),
                                    .init(name: "file", index: idDirFileA),
                                    .init(name: "file1", index: idDirFileB),
                                    .init(name: "file2", index: idDirFileC),
                                    .init(name: "file3", index: idDirFileD),
                                    .init(name: "file4", index: idDirFileE),
                                    .init(name: "file5", index: idDirFileF),
                                ]))

        let idRoot = self.files.count
        self.files.append(.init(type: .directory,
                                children: [
                                    .init(name: ".", index: idRoot),
                                    .init(name: "dir", index: idDir),
                                ]))

        self.files[idDir].children.append(.init(name: "..", index: idRoot))
        self.files[idRoot].children.append(.init(name: "..", index: idRoot))

        self.root = idRoot
    }

    func mount(_ call: MountCallMount, promise: EventLoopPromise<MountReplyMount>) {
        promise.succeed(.init(result: .okay(.init(fileHandle: NFS3FileHandle(UInt64(self.root))))))
    }

    func unmount(_ call: MountCallUnmount, promise: EventLoopPromise<MountReplyUnmount>) {
        promise.succeed(.init())
    }

    func getattr(_ call: NFS3CallGetAttr, promise: EventLoopPromise<NFS3ReplyGetAttr>) {
        if let result = self.getFile(call.fileHandle) {
            promise.succeed(.init(result: .okay(.init(attributes: result))))
        } else {
            promise.succeed(.init(result: .fail(.errorBADHANDLE, NFS3Nothing())))
        }
    }

    func lookup(fileName: String, inDirectory dirHandle: NFS3FileHandle) -> (NFS3FileHandle, NFS3FileAttr)? {
        guard let dirEntry = self.getEntry(fileHandle: dirHandle) else {
            return nil
        }

        guard let index = self.files[dirEntry.0].children.first(where: { $0.name == fileName })?.index else {
            return nil
        }
        let fileHandle = NFS3FileHandle(UInt64(index))

        return (fileHandle, self.getFile(fileHandle)!)
    }

    func getEntry(index: Int) -> InodeEntry? {
        guard index >= 0 && index < self.files.count else {
            return nil
        }
        return self.files[index]
    }

    func getEntry(fileHandle: NFS3FileHandle) -> (Int, InodeEntry)? {
        return UInt64(fileHandle).flatMap {
            Int(exactly: $0)
        }.flatMap { index in
            self.getEntry(index: index).map {
                (index, $0)
            }
        }
    }

    func getFile(_ fileHandle: NFS3FileHandle) -> NFS3FileAttr? {
        guard let entry = self.getEntry(fileHandle: fileHandle) else {
            return nil
        }

        return .init(type: entry.1.type,
                     mode: 0o777,
                     nlink: 1,
                     uid: 1,
                     gid: 1,
                     size: 1 * 1024 * 1024,
                     used: 1,
                     rdev: 1,
                     fsid: 1,
                     fileid: .init(entry.0),
                     atime: .init(seconds: 0, nanoSeconds: 0),
                     mtime: .init(seconds: 0, nanoSeconds: 0),
                     ctime: .init(seconds: 0, nanoSeconds: 0))
    }

    func fsinfo(_ call: NFS3CallFSInfo, promise: EventLoopPromise<NFS3ReplyFSInfo>) {
        promise.succeed(NFS3ReplyFSInfo(result: .okay(.init(attributes: nil,
                                                           rtmax: 1_000_000,
                                                           rtpref: 128_000,
                                                           rtmult: 4096,
                                                           wtmax: 1_000_000,
                                                           wtpref: 128_000,
                                                           wtmult: 4096,
                                                           dtpref: 128_000,
                                                           maxFileSize: UInt64(Int.max),
                                                           timeDelta: NFS3Time(seconds: 0, nanoSeconds: 0),
                                                           properties: .default))))
    }

    func pathconf(_ call: NFS3CallPathConf, promise: EventLoopPromise<NFS3ReplyPathConf>) {
        promise.succeed(.init(result: .okay(.init(attributes: nil,
                                                  linkMax: 1_000_000,
                                                  nameMax: 4096,
                                                  noTrunc: false,
                                                  chownRestricted: false,
                                                  caseInsensitive: false,
                                                  casePreserving: true))))
    }

    func fsstat(_ call: NFS3CallFSStat, promise: EventLoopPromise<NFS3ReplyFSStat>) {
        promise.succeed(.init(result: .okay(.init(attributes: nil,
                                                  tbytes: 0x10000000000,
                                                  fbytes: 0,
                                                  abytes: 0,
                                                  tfiles: 0x10000000,
                                                  ffiles: 0,
                                                  afiles: 0,
                                                  invarsec: 0))))
    }

    func access(_ call: NFS3CallAccess, promise: EventLoopPromise<NFS3ReplyAccess>) {
        promise.succeed(.init(result: .okay(.init(dirAttributes: nil, access: .allReadOnly))))
    }

    func lookup(_ call: NFS3CallLookup, promise: EventLoopPromise<NFS3ReplyLookup>) {
        if let entry = self.lookup(fileName: call.name, inDirectory: call.dir) {
            promise.succeed(.init(result: .okay(.init(fileHandle: entry.0,
                                                      attributes: entry.1,
                                                      dirAttributes: nil))))
        } else {
            promise.succeed(.init(result: .fail(.errorNOENT, .init(dirAttributes: nil))))

        }
    }

    func readdirplus(_ call: NFS3CallReadDirPlus, promise: EventLoopPromise<NFS3ReplyReadDirPlus>) {
        if let entry = self.getEntry(fileHandle: call.fileHandle) {
            var entries: [NFS3ReplyReadDirPlus.Entry] = []
            for fileIndex in entry.1.children.enumerated().dropFirst(Int(min(UInt64(Int.max), call.cookie))) {
                entries.append(.init(fileID: UInt64(fileIndex.element.index),
                                     fileName: fileIndex.element.name,
                                     cookie: NFS3Cookie(fileIndex.offset),
                                     nameAttributes: nil,
                                     nameHandle: nil))
            }
            promise.succeed(.init(result: .okay(.init(dirAttributes: nil,
                                                      cookieVerifier: call.cookieVerifier,
                                                      entries: entries,
                                                      eof: true))))
        } else {
            promise.succeed(.init(result: .fail(.errorNOENT, .init(dirAttributes: nil))))

        }
    }

    func read(_ call: NFS3CallRead, promise: EventLoopPromise<NFS3ReplyRead>) {
        if let file = self.getFile(call.fileHandle) {
            if file.type == .regular {
                var slice = self.fileContent
                guard call.offset <= .init(Int.max) else {
                    promise.succeed(.init(result: .fail(.errorFBIG, .init(attributes: nil))))
                    return
                }
                let offsetLegal = slice.readSlice(length: Int(call.offset)) != nil
                if offsetLegal {
                    let actualSlice = slice.readSlice(length: min(slice.readableBytes, Int(call.count)))!
                    let isEOF = slice.readableBytes == 0

                    promise.succeed(.init(result: .okay(.init(attributes: nil,
                                                              count: .init(actualSlice.readableBytes),
                                                              eof: isEOF,
                                                              data: actualSlice))))
                } else {
                    promise.succeed(.init(result: .okay(.init(attributes: nil,
                                                              count: 0,
                                                              eof: true,
                                                              data: ByteBuffer()))))
                }
            } else {
                promise.succeed(.init(result: .fail(.errorISDIR, .init(attributes: nil))))
            }
        } else {
            promise.succeed(.init(result: .fail(.errorNOENT, .init(attributes: nil))))
        }
    }

    func readlink(_ call: NFS3CallReadlink, promise: EventLoopPromise<NFS3ReplyReadlink>) {
        promise.succeed(.init(result: .fail(.errorNOENT, .init(symlinkAttributes: nil))))
    }

    func setattr(_ call: NFS3CallSetattr, promise: EventLoopPromise<NFS3ReplySetattr>) {
        promise.succeed(.init(result: .fail(.errorROFS, .init(wcc: .init(before: nil, after: nil)))))
    }

    func shutdown(promise: EventLoopPromise<Void>) {
        promise.succeed(())
    }
}
