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

@preconcurrency
public protocol NFS3FileSystemNoAuth: Sendable {
    // Must be Sendable; there are extensions which take an event loop and call these functions
    // on that event loop.

    func mount(_ call: MountCallMount, promise: EventLoopPromise<MountReplyMount>)
    func unmount(_ call: MountCallUnmount, promise: EventLoopPromise<MountReplyUnmount>)
    func getattr(_ call: NFS3CallGetAttr, promise: EventLoopPromise<NFS3ReplyGetAttr>)
    func fsinfo(_ call: NFS3CallFSInfo, promise: EventLoopPromise<NFS3ReplyFSInfo>)
    func pathconf(_ call: NFS3CallPathConf, promise: EventLoopPromise<NFS3ReplyPathConf>)
    func fsstat(_ call: NFS3CallFSStat, promise: EventLoopPromise<NFS3ReplyFSStat>)
    func access(_ call: NFS3CallAccess, promise: EventLoopPromise<NFS3ReplyAccess>)
    func lookup(_ call: NFS3CallLookup, promise: EventLoopPromise<NFS3ReplyLookup>)
    func readdirplus(_ call: NFS3CallReadDirPlus, promise: EventLoopPromise<NFS3ReplyReadDirPlus>)
    func read(_ call: NFS3CallRead, promise: EventLoopPromise<NFS3ReplyRead>)
    func readlink(_ call: NFS3CallReadlink, promise: EventLoopPromise<NFS3ReplyReadlink>)
    func setattr(_ call: NFS3CallSetattr, promise: EventLoopPromise<NFS3ReplySetattr>)
    func readdir(_ call: NFS3CallReadDir, promise: EventLoopPromise<NFS3ReplyReadDir>)

    func shutdown(promise: EventLoopPromise<Void>)
}

extension NFS3FileSystemNoAuth {
    public func readdir(_ call: NFS3CallReadDir, promise originalPromise: EventLoopPromise<NFS3ReplyReadDir>) {
        let promise = originalPromise.futureResult.eventLoop.makePromise(of: NFS3ReplyReadDirPlus.self)
        self.readdirplus(
            NFS3CallReadDirPlus(
                fileHandle: call.fileHandle,
                cookie: call.cookie,
                cookieVerifier: call.cookieVerifier,
                dirCount: NFS3Count(rawValue: .max),
                maxCount: call.maxResultByteCount
            ),

            promise: promise
        )

        promise.futureResult.whenComplete { readDirPlusResult in
            switch readDirPlusResult {
            case .success(let readDirPlusSuccessResult):
                switch readDirPlusSuccessResult.result {
                case .okay(let readDirPlusOkay):
                    originalPromise.succeed(
                        NFS3ReplyReadDir(
                            result: .okay(
                                .init(
                                    cookieVerifier: readDirPlusOkay.cookieVerifier,
                                    entries: readDirPlusOkay.entries.map { readDirPlusEntry in
                                        NFS3ReplyReadDir.Entry(
                                            fileID: readDirPlusEntry.fileID,
                                            fileName: readDirPlusEntry.fileName,
                                            cookie: readDirPlusEntry.cookie
                                        )
                                    },
                                    eof: readDirPlusOkay.eof
                                )
                            )
                        )
                    )
                case .fail(let nfsStatus, let readDirPlusFailure):
                    originalPromise.succeed(
                        NFS3ReplyReadDir(
                            result: .fail(
                                nfsStatus,
                                .init(dirAttributes: readDirPlusFailure.dirAttributes)
                            )
                        )
                    )

                }
            case .failure(let error):
                originalPromise.fail(error)
            }
        }
    }
}
