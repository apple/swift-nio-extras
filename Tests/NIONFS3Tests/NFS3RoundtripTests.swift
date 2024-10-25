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
import NIONFS3
import NIOTestUtils
import XCTest

final class NFS3RoundtripTests: XCTestCase {
    func testRegularCallsRoundtrip() {
        let mountCallNull = NFS3Call.mountNull(.init())
        let mountCall1 = NFS3Call.mount(MountCallMount(dirPath: "/hellö/this is/a cOmplicatedPath⚠️"))
        let mountCall2 = NFS3Call.mount(MountCallMount(dirPath: ""))
        let unmountCall1 = NFS3Call.unmount(MountCallUnmount(dirPath: "/hellö/this is/a cOmplicatedPath⚠️"))
        let accessCall1 = NFS3Call.access(NFS3CallAccess(object: NFS3FileHandle(#line), access: .all))
        let fsInfoCall1 = NFS3Call.fsinfo(.init(fsroot: NFS3FileHandle(#line)))
        let fsStatCall1 = NFS3Call.fsstat(.init(fsroot: NFS3FileHandle(#line)))
        let getattrCall1 = NFS3Call.getattr(.init(fileHandle: NFS3FileHandle(#line)))
        let lookupCall1 = NFS3Call.lookup(.init(dir: NFS3FileHandle(#line), name: "⚠️"))
        let nullCall1 = NFS3Call.null(.init())
        let pathConfCall1 = NFS3Call.pathconf(.init(object: NFS3FileHandle(#line)))
        let readCall1 = NFS3Call.read(.init(fileHandle: NFS3FileHandle(#line), offset: 123, count: 456))
        let readDirPlusCall1 = NFS3Call.readdirplus(
            .init(
                fileHandle: NFS3FileHandle(#line),
                cookie: 345,
                cookieVerifier: 879,
                dirCount: 23488,
                maxCount: 2_342_888
            )
        )
        let readDirCall1 = NFS3Call.readdir(
            .init(fileHandle: NFS3FileHandle(#line), cookie: 345, cookieVerifier: 879, maxResultByteCount: 234797)
        )
        let readlinkCall1 = NFS3Call.readlink(.init(symlink: NFS3FileHandle(#line)))
        let setattrCall1 = NFS3Call.setattr(
            .init(
                object: NFS3FileHandle(#line),
                newAttributes: .init(
                    mode: 0o146,
                    uid: 1,
                    gid: 2,
                    size: 3,
                    atime: .init(seconds: 4, nanoseconds: 5),
                    mtime: .init(seconds: 6, nanoseconds: 7)
                ),
                guard: .init(seconds: 8, nanoseconds: 0)
            )
        )

        var xid: UInt32 = 0
        func makeInputOutputPair(_ nfsCall: NFS3Call) -> (ByteBuffer, [RPCNFS3Call]) {
            var buffer = ByteBuffer()
            xid += 1
            let rpcNFS3Call = RPCNFS3Call(nfsCall: nfsCall, xid: xid)
            let oldReadableBytes = buffer.readableBytes
            let bytesWritten = buffer.writeRPCNFS3Call(rpcNFS3Call)
            XCTAssertEqual(oldReadableBytes + bytesWritten, buffer.readableBytes)

            return (buffer, [rpcNFS3Call])
        }

        XCTAssertNoThrow(
            try ByteToMessageDecoderVerifier.verifyDecoder(
                inputOutputPairs: [
                    makeInputOutputPair(mountCall1),
                    makeInputOutputPair(mountCall2),
                    makeInputOutputPair(unmountCall1),
                    makeInputOutputPair(accessCall1),
                    makeInputOutputPair(fsInfoCall1),
                    makeInputOutputPair(fsStatCall1),
                    makeInputOutputPair(getattrCall1),
                    makeInputOutputPair(lookupCall1),
                    makeInputOutputPair(nullCall1),
                    makeInputOutputPair(mountCallNull),
                    makeInputOutputPair(pathConfCall1),
                    makeInputOutputPair(readCall1),
                    makeInputOutputPair(readDirCall1),
                    makeInputOutputPair(readDirPlusCall1),
                    makeInputOutputPair(readlinkCall1),
                    makeInputOutputPair(setattrCall1),
                ],
                decoderFactory: { NFS3CallDecoder() }
            )
        )
    }

    func testCallsWithMaxIntegersRoundtrip() {
        let accessCall1 = NFS3Call.access(
            NFS3CallAccess(
                object: NFS3FileHandle(.max),
                access: NFS3Access(rawValue: .max)
            )
        )
        let fsInfoCall1 = NFS3Call.fsinfo(.init(fsroot: NFS3FileHandle(.max)))
        let fsStatCall1 = NFS3Call.fsstat(.init(fsroot: NFS3FileHandle(.max)))
        let getattrCall1 = NFS3Call.getattr(.init(fileHandle: NFS3FileHandle(.max)))
        let lookupCall1 = NFS3Call.lookup(.init(dir: NFS3FileHandle(.max), name: "⚠️"))
        let pathConfCall1 = NFS3Call.pathconf(.init(object: NFS3FileHandle(.max)))
        let readCall1 = NFS3Call.read(
            .init(
                fileHandle: NFS3FileHandle(.max),
                offset: .init(rawValue: .max),
                count: .init(rawValue: .max)
            )
        )
        let readDirPlusCall1 = NFS3Call.readdirplus(
            .init(
                fileHandle: NFS3FileHandle(.max),
                cookie: .init(rawValue: .max),
                cookieVerifier: .init(rawValue: .max),
                dirCount: .init(rawValue: .max),
                maxCount: .init(rawValue: .max)
            )
        )
        let readDirCall1 = NFS3Call.readdir(
            .init(
                fileHandle: NFS3FileHandle(.max),
                cookie: .init(rawValue: .max),
                cookieVerifier: .init(rawValue: .max),
                maxResultByteCount: .init(rawValue: .max)
            )
        )
        let readlinkCall1 = NFS3Call.readlink(.init(symlink: NFS3FileHandle(.max)))
        let setattrCall1 = NFS3Call.setattr(
            .init(
                object: NFS3FileHandle(.max),
                newAttributes: .init(
                    mode: .init(rawValue: .max),
                    uid: .init(rawValue: .max),
                    gid: .init(rawValue: .max),
                    size: .init(rawValue: .max),
                    atime: .init(seconds: .max, nanoseconds: .max),
                    mtime: .init(seconds: .max, nanoseconds: .max)
                ),
                guard: .init(seconds: .max, nanoseconds: .max)
            )
        )

        var xid: UInt32 = 0
        func makeInputOutputPair(_ nfsCall: NFS3Call) -> (ByteBuffer, [RPCNFS3Call]) {
            var buffer = ByteBuffer()
            xid += 1
            let rpcNFS3Call = RPCNFS3Call(nfsCall: nfsCall, xid: xid)
            let oldReadableBytes = buffer.readableBytes
            let bytesWritten = buffer.writeRPCNFS3Call(rpcNFS3Call)
            XCTAssertEqual(oldReadableBytes + bytesWritten, buffer.readableBytes)

            return (buffer, [rpcNFS3Call])
        }

        XCTAssertNoThrow(
            try ByteToMessageDecoderVerifier.verifyDecoder(
                inputOutputPairs: [
                    makeInputOutputPair(accessCall1),
                    makeInputOutputPair(fsInfoCall1),
                    makeInputOutputPair(fsStatCall1),
                    makeInputOutputPair(getattrCall1),
                    makeInputOutputPair(lookupCall1),
                    makeInputOutputPair(pathConfCall1),
                    makeInputOutputPair(readCall1),
                    makeInputOutputPair(readDirPlusCall1),
                    makeInputOutputPair(readDirCall1),
                    makeInputOutputPair(readlinkCall1),
                    makeInputOutputPair(setattrCall1),
                ],
                decoderFactory: { NFS3CallDecoder() }
            )
        )
    }

    func testRegularOkayRepliesRoundtrip() {
        func makeRandomFileAttr() -> NFS3FileAttr {
            .init(
                type: .init(rawValue: .random(in: 1...7))!,
                mode: .init(rawValue: .random(in: 0o000...0o777)),
                nlink: .random(in: .min ... .max),
                uid: .init(rawValue: .random(in: .min ... .max)),
                gid: .init(rawValue: .random(in: .min ... .max)),
                size: .init(rawValue: .random(in: .min ... .max)),
                used: .init(rawValue: .random(in: .min ... .max)),
                rdev: .init(rawValue: .random(in: .min ... .max)),
                fsid: .random(in: .min ... .max),
                fileid: .init(rawValue: .random(in: .min ... .max)),
                atime: .init(
                    seconds: .random(in: .min ... .max),
                    nanoseconds: .random(in: .min ... .max)
                ),
                mtime: .init(
                    seconds: .random(in: .min ... .max),
                    nanoseconds: .random(in: .min ... .max)
                ),
                ctime: .init(
                    seconds: .random(in: .min ... .max),
                    nanoseconds: .random(in: .min ... .max)
                )
            )
        }
        let mountNullReply1 = NFS3Reply.mountNull
        let mountReply1 = NFS3Reply.mount(MountReplyMount(result: .okay(.init(fileHandle: NFS3FileHandle(#line)))))
        let mountReply2 = NFS3Reply.mount(.init(result: .okay(.init(fileHandle: NFS3FileHandle(#line)))))
        let unmountReply1 = NFS3Reply.unmount(.init())
        let accessReply1 = NFS3Reply.access(
            .init(result: .okay(.init(dirAttributes: makeRandomFileAttr(), access: .allReadOnly)))
        )
        let fsInfoReply1 = NFS3Reply.fsinfo(
            .init(
                result:
                    .okay(
                        .init(
                            attributes: makeRandomFileAttr(),
                            rtmax: .random(in: .min ... .max),
                            rtpref: .random(in: .min ... .max),
                            rtmult: .random(in: .min ... .max),
                            wtmax: .random(in: .min ... .max),
                            wtpref: .random(in: .min ... .max),
                            wtmult: .random(in: .min ... .max),
                            dtpref: .random(in: .min ... .max),
                            maxFileSize: .init(rawValue: .random(in: .min ... .max)),
                            timeDelta: .init(
                                seconds: .random(in: .min ... .max),
                                nanoseconds: .random(in: .min ... .max)
                            ),
                            properties: .init(rawValue: .random(in: .min ... .max))
                        )
                    )
            )
        )
        let fsStatReply1 = NFS3Reply.fsstat(
            .init(
                result:
                    .okay(
                        .init(
                            attributes: makeRandomFileAttr(),
                            tbytes: .init(rawValue: .random(in: .min ... .max)),
                            fbytes: .init(rawValue: .random(in: .min ... .max)),
                            abytes: .init(rawValue: .random(in: .min ... .max)),
                            tfiles: .init(rawValue: .random(in: .min ... .max)),
                            ffiles: .init(rawValue: .random(in: .min ... .max)),
                            afiles: .init(rawValue: .random(in: .min ... .max)),
                            invarsec: .random(in: .min ... .max)
                        )
                    )
            )
        )
        let getattrReply1 = NFS3Reply.getattr(.init(result: .okay(.init(attributes: makeRandomFileAttr()))))
        let lookupReply1 = NFS3Reply.lookup(
            .init(
                result:
                    .okay(
                        .init(
                            fileHandle: NFS3FileHandle(.random(in: .min ... .max)),
                            attributes: makeRandomFileAttr(),
                            dirAttributes: makeRandomFileAttr()
                        )
                    )
            )
        )
        let nullReply1 = NFS3Reply.null
        let pathConfReply1 = NFS3Reply.pathconf(
            .init(
                result: .okay(
                    .init(
                        attributes: makeRandomFileAttr(),
                        linkMax: .random(in: .min ... .max),
                        nameMax: .random(in: .min ... .max),
                        noTrunc: .random(),
                        chownRestricted: .random(),
                        caseInsensitive: .random(),
                        casePreserving: .random()
                    )
                )
            )
        )
        let readReply1 = NFS3Reply.read(
            .init(
                result: .okay(
                    .init(
                        attributes: makeRandomFileAttr(),
                        count: .init(rawValue: .random(in: .min ... .max)),
                        eof: .random(),
                        data: ByteBuffer(string: "abc")
                    )
                )
            )
        )
        let readDirPlusReply1 = NFS3Reply.readdirplus(
            .init(
                result:
                    .okay(
                        .init(
                            dirAttributes: makeRandomFileAttr(),
                            cookieVerifier: .init(rawValue: .random(in: .min ... .max)),
                            entries: [
                                .init(
                                    fileID: .init(rawValue: .random(in: .min ... .max)),
                                    fileName: "asd",
                                    cookie: .init(rawValue: .random(in: .min ... .max)),
                                    nameAttributes: makeRandomFileAttr(),
                                    nameHandle: NFS3FileHandle(.random(in: .min ... .max))
                                )
                            ],
                            eof: .random()
                        )
                    )
            )
        )
        let readDirReply1 = NFS3Reply.readdir(
            .init(
                result:
                    .okay(
                        .init(
                            dirAttributes: makeRandomFileAttr(),
                            cookieVerifier: .init(rawValue: .random(in: .min ... .max)),
                            entries: [
                                .init(
                                    fileID: .init(rawValue: .random(in: .min ... .max)),
                                    fileName: "asd",
                                    cookie: .init(rawValue: .random(in: .min ... .max))
                                )
                            ],
                            eof: .random()
                        )
                    )
            )
        )
        let readlinkReply1 = NFS3Reply.readlink(
            .init(
                result: .okay(
                    .init(
                        symlinkAttributes: makeRandomFileAttr(),
                        target: "he"
                    )
                )
            )
        )
        let setattrReply1 = NFS3Reply.setattr(
            .init(
                result:
                    .okay(
                        .init(
                            wcc: .init(
                                before: .some(
                                    .init(
                                        size: .init(rawValue: .random(in: .min ... .max)),
                                        mtime: .init(
                                            seconds: .random(in: .min ... .max),
                                            nanoseconds: .random(in: .min ... .max)
                                        ),
                                        ctime: .init(
                                            seconds: .random(in: .min ... .max),
                                            nanoseconds: .random(in: .min ... .max)
                                        )
                                    )
                                ),
                                after: makeRandomFileAttr()
                            )
                        )
                    )
            )
        )

        var xid: UInt32 = 0
        var prepopulatedProcs: [UInt32: RPCNFS3ProcedureID] = [:]
        func makeInputOutputPair(_ nfsReply: NFS3Reply) -> (ByteBuffer, [RPCNFS3Reply]) {
            var buffer = ByteBuffer()
            xid += 1
            let rpcNFS3Reply = RPCNFS3Reply(
                rpcReply:
                    .init(
                        xid: xid,
                        status: .messageAccepted(
                            .init(
                                verifier: .init(flavor: .noAuth, opaque: nil),
                                status: .success
                            )
                        )
                    ),
                nfsReply: nfsReply
            )
            prepopulatedProcs[xid] = .init(nfsReply)
            let oldReadableBytes = buffer.readableBytes
            let writtenBytes = buffer.writeRPCNFS3Reply(rpcNFS3Reply)
            XCTAssertEqual(oldReadableBytes + writtenBytes, buffer.readableBytes)

            return (buffer, [rpcNFS3Reply])
        }

        XCTAssertNoThrow(
            try ByteToMessageDecoderVerifier.verifyDecoder(
                inputOutputPairs: [
                    makeInputOutputPair(mountNullReply1),
                    makeInputOutputPair(mountReply1),
                    makeInputOutputPair(mountReply2),
                    makeInputOutputPair(unmountReply1),
                    makeInputOutputPair(accessReply1),
                    makeInputOutputPair(fsInfoReply1),
                    makeInputOutputPair(fsStatReply1),
                    makeInputOutputPair(getattrReply1),
                    makeInputOutputPair(lookupReply1),
                    makeInputOutputPair(nullReply1),
                    makeInputOutputPair(pathConfReply1),
                    makeInputOutputPair(readReply1),
                    makeInputOutputPair(readDirPlusReply1),
                    makeInputOutputPair(readDirReply1),
                    makeInputOutputPair(readlinkReply1),
                    makeInputOutputPair(setattrReply1),
                ],
                decoderFactory: {
                    NFS3ReplyDecoder(
                        prepopulatedProcecedures: prepopulatedProcs,
                        allowDuplicateReplies: true
                    )
                }
            )
        )
    }
}
