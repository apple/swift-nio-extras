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
import NIOEmbedded
import NIONFS3
import XCTest

final class NFS3FileSystemTests: XCTestCase {
    func testReadDirDefaultImplementation() throws {
        final class MyOnlyReadDirPlusFS: NFS3FileSystemNoAuth {
            func shutdown(promise: EventLoopPromise<Void>) {
                promise.succeed(())
            }

            func readdirplus(_ call: NFS3CallReadDirPlus, promise: EventLoopPromise<NFS3ReplyReadDirPlus>) {
                promise.succeed(
                    .init(
                        result: .okay(
                            .init(
                                cookieVerifier: .init(rawValue: 11111),
                                entries: [
                                    .init(
                                        fileID: .init(rawValue: 22222),
                                        fileName: "file",
                                        cookie: .init(rawValue: 33333)
                                    )
                                ],
                                eof: true
                            )
                        )
                    )
                )
            }

            func mount(_ call: MountCallMount, promise: EventLoopPromise<MountReplyMount>) {
                fatalError("shouldn't be called")
            }

            func unmount(_ call: MountCallUnmount, promise: EventLoopPromise<MountReplyUnmount>) {
                fatalError("shouldn't be called")
            }

            func getattr(_ call: NFS3CallGetAttr, promise: EventLoopPromise<NFS3ReplyGetAttr>) {
                fatalError("shouldn't be called")
            }

            func fsinfo(_ call: NFS3CallFSInfo, promise: EventLoopPromise<NFS3ReplyFSInfo>) {
                fatalError("shouldn't be called")
            }

            func pathconf(_ call: NFS3CallPathConf, promise: EventLoopPromise<NFS3ReplyPathConf>) {
                fatalError("shouldn't be called")
            }

            func fsstat(_ call: NFS3CallFSStat, promise: EventLoopPromise<NFS3ReplyFSStat>) {
                fatalError("shouldn't be called")
            }

            func access(_ call: NFS3CallAccess, promise: EventLoopPromise<NFS3ReplyAccess>) {
                fatalError("shouldn't be called")
            }

            func lookup(_ call: NFS3CallLookup, promise: EventLoopPromise<NFS3ReplyLookup>) {
                fatalError("shouldn't be called")
            }

            func read(_ call: NFS3CallRead, promise: EventLoopPromise<NFS3ReplyRead>) {
                fatalError("shouldn't be called")
            }

            func readlink(_ call: NFS3CallReadlink, promise: EventLoopPromise<NFS3ReplyReadlink>) {
                fatalError("shouldn't be called")
            }

            func setattr(_ call: NFS3CallSetattr, promise: EventLoopPromise<NFS3ReplySetattr>) {
                fatalError("shouldn't be called")
            }
        }

        let eventLoop = EmbeddedEventLoop()
        defer {
            XCTAssertNoThrow(try eventLoop.syncShutdownGracefully())
        }
        let fs = MyOnlyReadDirPlusFS()
        let promise = eventLoop.makePromise(of: NFS3ReplyReadDir.self)
        fs.readdir(
            .init(
                fileHandle: .init(123),
                cookie: .init(rawValue: 234),
                cookieVerifier: .init(rawValue: 345),
                maxResultByteCount: .init(rawValue: 456)
            ),
            promise: promise
        )
        let actualResult = try promise.futureResult.wait()
        let expectedResult = NFS3ReplyReadDir(
            result: .okay(
                .init(
                    cookieVerifier: .init(rawValue: 11111),
                    entries: [
                        .init(
                            fileID: .init(rawValue: 22222),
                            fileName: "file",
                            cookie: .init(rawValue: 33333)
                        )
                    ],
                    eof: true
                )
            )
        )
        XCTAssertEqual(expectedResult, actualResult)
    }
}
