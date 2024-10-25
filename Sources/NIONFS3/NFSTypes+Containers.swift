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

public struct RPCNFS3ProcedureID: Hashable & Sendable {
    public internal(set) var program: UInt32
    public internal(set) var procedure: UInt32

    public static let mountNull: Self = .init(program: 100005, procedure: 0)
    public static let mountMount: Self = .init(program: 100005, procedure: 1)
    public static let mountDump: Self = .init(program: 100005, procedure: 2)  // unimplemented
    public static let mountUnmount: Self = .init(program: 100005, procedure: 3)
    public static let mountUnmountAll: Self = .init(program: 100005, procedure: 4)  // unimplemented
    public static let mountExport: Self = .init(program: 100005, procedure: 5)  // unimplemented

    // The source of truth for the values in the NFS program (`1000003`) can be found in the NFS RFC at
    // https://www.rfc-editor.org/rfc/rfc1813#page-28
    public static let nfsNull: Self = .init(program: 100003, procedure: 0)
    public static let nfsGetAttr: Self = .init(program: 100003, procedure: 1)
    public static let nfsSetAttr: Self = .init(program: 100003, procedure: 2)
    public static let nfsLookup: Self = .init(program: 100003, procedure: 3)
    public static let nfsAccess: Self = .init(program: 100003, procedure: 4)
    public static let nfsReadLink: Self = .init(program: 100003, procedure: 5)
    public static let nfsRead: Self = .init(program: 100003, procedure: 6)

    public static let nfsWrite: Self = .init(program: 100003, procedure: 7)  // unimplemented
    public static let nfsCreate: Self = .init(program: 100003, procedure: 8)  // unimplemented
    public static let nfsMkDir: Self = .init(program: 100003, procedure: 9)  // unimplemented
    public static let nfsSymlink: Self = .init(program: 100003, procedure: 10)  // unimplemented
    public static let nfsMkNod: Self = .init(program: 100003, procedure: 11)  // unimplemented
    public static let nfsRemove: Self = .init(program: 100003, procedure: 12)  // unimplemented
    public static let nfsRmDir: Self = .init(program: 100003, procedure: 13)  // unimplemented
    public static let nfsRename: Self = .init(program: 100003, procedure: 14)  // unimplemented
    public static let nfsLink: Self = .init(program: 100003, procedure: 15)  // unimplemented
    public static let nfsReadDir: Self = .init(program: 100003, procedure: 16)

    public static let nfsReadDirPlus: Self = .init(program: 100003, procedure: 17)
    public static let nfsFSStat: Self = .init(program: 100003, procedure: 18)
    public static let nfsFSInfo: Self = .init(program: 100003, procedure: 19)
    public static let nfsPathConf: Self = .init(program: 100003, procedure: 20)

    public static let nfsCommit: Self = .init(program: 100003, procedure: 21)  // unimplemented
}

extension RPCNFS3ProcedureID {
    public init(_ nfsReply: NFS3Reply) {
        switch nfsReply {
        case .mountNull:
            self = .mountNull
        case .mount:
            self = .mountMount
        case .unmount:
            self = .mountUnmount
        case .null:
            self = .nfsNull
        case .getattr:
            self = .nfsGetAttr
        case .fsinfo:
            self = .nfsFSInfo
        case .pathconf:
            self = .nfsPathConf
        case .fsstat:
            self = .nfsFSStat
        case .access:
            self = .nfsAccess
        case .lookup:
            self = .nfsLookup
        case .readdirplus:
            self = .nfsReadDirPlus
        case .readdir:
            self = .nfsReadDir
        case .read:
            self = .nfsRead
        case .readlink:
            self = .nfsReadLink
        case .setattr:
            self = .nfsSetAttr
        case ._PLEASE_DO_NOT_EXHAUSTIVELY_MATCH_THIS_ENUM_NEW_CASES_MIGHT_BE_ADDED_IN_THE_FUTURE:
            // inside the module, matching exhaustively is okay
            preconditionFailure("unknown NFS3 reply, this should never happen. Please report a bug.")
        }
    }
}

public enum NFS3Call: Hashable & Sendable {
    case mountNull(MountCallNull)
    case mount(MountCallMount)
    case unmount(MountCallUnmount)
    case null(NFS3CallNull)
    case getattr(NFS3CallGetAttr)
    case fsinfo(NFS3CallFSInfo)
    case pathconf(NFS3CallPathConf)
    case fsstat(NFS3CallFSStat)
    case access(NFS3CallAccess)
    case lookup(NFS3CallLookup)
    case readdirplus(NFS3CallReadDirPlus)
    case read(NFS3CallRead)
    case readlink(NFS3CallReadlink)
    case setattr(NFS3CallSetattr)
    case readdir(NFS3CallReadDir)

    case _PLEASE_DO_NOT_EXHAUSTIVELY_MATCH_THIS_ENUM_NEW_CASES_MIGHT_BE_ADDED_IN_THE_FUTURE
}

public enum NFS3Reply: Hashable & Sendable {
    case mountNull
    case mount(MountReplyMount)
    case unmount(MountReplyUnmount)
    case null
    case getattr(NFS3ReplyGetAttr)
    case fsinfo(NFS3ReplyFSInfo)
    case pathconf(NFS3ReplyPathConf)
    case fsstat(NFS3ReplyFSStat)
    case access(NFS3ReplyAccess)
    case lookup(NFS3ReplyLookup)
    case readdirplus(NFS3ReplyReadDirPlus)
    case readdir(NFS3ReplyReadDir)
    case read(NFS3ReplyRead)
    case readlink(NFS3ReplyReadlink)
    case setattr(NFS3ReplySetattr)

    case _PLEASE_DO_NOT_EXHAUSTIVELY_MATCH_THIS_ENUM_NEW_CASES_MIGHT_BE_ADDED_IN_THE_FUTURE
}

public enum NFS3Error: Error {
    case wrongMessageType(RPCMessage)
    case unknownProgramOrProcedure(RPCMessage)
    case invalidFileHandleFormat(length: UInt32)
    case illegalRPCTooShort
    case invalidFileType(UInt32)
    case invalidStatus(UInt32)
    case invalidFSInfoProperties(NFS3ReplyFSInfo.Properties)
    case unknownXID(UInt32)

    case _PLEASE_DO_NOT_EXHAUSTIVELY_MATCH_THIS_ENUM_NEW_CASES_MIGHT_BE_ADDED_IN_THE_FUTURE
}

internal func nfsStringFillBytes(_ byteCount: Int) -> Int {
    (4 - (byteCount % 4)) % 4
}

extension ByteBuffer {
    public mutating func readRPCVerifier() throws -> RPCOpaqueAuth {
        guard let (flavor, length) = self.readMultipleIntegers(as: (UInt32, UInt32).self) else {
            throw NFS3Error.illegalRPCTooShort
        }
        guard (flavor == RPCAuthFlavor.system.rawValue || flavor == RPCAuthFlavor.noAuth.rawValue) && length == 0 else {
            throw RPCErrors.unknownVerifier(flavor)
        }
        return RPCOpaqueAuth(flavor: .noAuth, opaque: nil)
    }

    @discardableResult public mutating func writeRPCVerifier(_ verifier: RPCOpaqueAuth) -> Int {
        var bytesWritten = self.writeInteger(verifier.flavor.rawValue)
        if let opaqueBlob = verifier.opaque {
            bytesWritten += self.writeNFS3Blob(opaqueBlob)
        } else {
            bytesWritten += self.writeInteger(0, as: UInt32.self)
        }
        return bytesWritten
    }

    public mutating func readRPCCredentials() throws -> RPCCredentials {
        guard let flavor = self.readInteger(as: UInt32.self) else {
            throw NFS3Error.illegalRPCTooShort
        }
        let blob = try self.readNFS3Blob()
        return RPCCredentials(flavor: flavor, length: UInt32(blob.readableBytes), otherBytes: blob)
    }

    @discardableResult public mutating func writeRPCCredentials(_ credentials: RPCCredentials) -> Int {
        self.writeInteger(credentials.flavor)
            + self.writeNFS3Blob(credentials.otherBytes)
    }

    public mutating func readRPCFragmentHeader() throws -> RPCFragmentHeader? {
        let save = self
        guard let lastAndLength = self.readInteger(as: UInt32.self) else {
            self = save
            return nil
        }
        return .init(rawValue: lastAndLength)
    }

    @discardableResult
    public mutating func setRPCFragmentHeader(_ header: RPCFragmentHeader, at index: Int) -> Int {
        self.setInteger(header.rawValue, at: index)
    }

    @discardableResult public mutating func writeRPCFragmentHeader(_ header: RPCFragmentHeader) -> Int {
        let bytesWritten = self.setRPCFragmentHeader(header, at: self.writerIndex)
        self.moveWriterIndex(forwardBy: bytesWritten)
        return bytesWritten
    }

    mutating func readRPCReply(xid: UInt32) throws -> RPCReply {
        let acceptedOrDenied = try self.readNFS3Integer(as: UInt32.self)
        switch acceptedOrDenied {
        case 0:  // MSG_ACCEPTED
            let verifier = try self.readRPCVerifier()
            let status = try self.readNFS3Integer(as: UInt32.self)
            let acceptedReplyStatus: RPCAcceptedReplyStatus

            switch status {
            case 0:  // SUCCESS
                acceptedReplyStatus = .success
            case 1:  //PROG_UNAVAIL
                acceptedReplyStatus = .programUnavailable
            case 2:  //PROG_MISMATCH
                guard let values = self.readMultipleIntegers(as: (UInt32, UInt32).self) else {
                    throw NFS3Error.illegalRPCTooShort
                }
                acceptedReplyStatus = .programMismatch(low: values.0, high: values.1)
            case 3:  //PROC_UNAVAIL
                acceptedReplyStatus = .procedureUnavailable
            case 4:  //GARBAGE_ARGS
                acceptedReplyStatus = .garbageArguments
            case 5:  //SYSTEM_ERR
                acceptedReplyStatus = .systemError
            default:
                throw RPCErrors.illegalReplyAcceptanceStatus(status)
            }
            return RPCReply(
                xid: xid,
                status: .messageAccepted(
                    .init(
                        verifier: verifier,
                        status: acceptedReplyStatus
                    )
                )
            )
        case 1:  // MSG_DENIED
            let rejectionKind = try self.readNFS3Integer(as: UInt32.self)
            switch rejectionKind {
            case 0:  // RPC_MISMATCH: RPC version number != 2
                guard let values = self.readMultipleIntegers(as: (UInt32, UInt32).self) else {
                    throw NFS3Error.illegalRPCTooShort
                }
                return RPCReply(xid: xid, status: .messageDenied(.rpcMismatch(low: values.0, high: values.1)))
            case 1:  // AUTH_ERROR
                let rawValue = try self.readNFS3Integer(as: UInt32.self)
                if let value = RPCAuthStatus(rawValue: rawValue) {
                    return RPCReply(xid: xid, status: .messageDenied(.authError(value)))
                } else {
                    throw RPCErrors.illegalAuthStatus(rawValue)
                }
            default:
                throw RPCErrors.illegalReplyRejectionStatus(rejectionKind)
            }
        default:
            throw RPCErrors.illegalReplyStatus(acceptedOrDenied)
        }
    }

    @discardableResult public mutating func writeRPCCall(_ call: RPCCall) -> Int {
        self.writeMultipleIntegers(
            RPCMessageType.call.rawValue,
            call.rpcVersion,
            call.program,
            call.programVersion,
            call.procedure
        )
            + self.writeRPCCredentials(call.credentials)
            + self.writeRPCVerifier(call.verifier)
    }

    @discardableResult public mutating func writeRPCReply(_ reply: RPCReply) -> Int {
        var bytesWritten = self.writeInteger(RPCMessageType.reply.rawValue)

        switch reply.status {
        case .messageAccepted(_):
            bytesWritten += self.writeInteger(0, as: UInt32.self)  // 0 -> accepted
        case .messageDenied(_):
            // FIXME: MSG_DENIED (spec name) isn't actually handled correctly here.
            bytesWritten += self.writeInteger(1, as: UInt32.self)  // 1 -> denied
        }
        bytesWritten +=
            self.writeInteger(0, as: UInt64.self)  // 0 -> verifier
            + self.writeInteger(0, as: UInt32.self)  // 0 -> executed successfully
        return bytesWritten
    }

    public mutating func readRPCCall(xid: UInt32) throws -> RPCCall {
        guard let values = self.readMultipleIntegers(as: (UInt32, UInt32, UInt32, UInt32).self) else {
            throw NFS3Error.illegalRPCTooShort
        }

        let (version, program, programVersion, procedure) = values
        let credentials = try self.readRPCCredentials()
        let verifier = try self.readRPCVerifier()

        guard version == 2 else {
            throw RPCErrors.unknownVersion(version)
        }

        return RPCCall(
            xid: xid,
            rpcVersion: version,
            program: program,
            programVersion: programVersion,
            procedure: procedure,
            credentials: credentials,
            verifier: verifier
        )
    }

    public mutating func readNFS3Reply(
        programAndProcedure: RPCNFS3ProcedureID,
        rpcReply: RPCReply
    ) throws -> RPCNFS3Reply {
        switch programAndProcedure {
        case .mountNull:
            return .init(rpcReply: rpcReply, nfsReply: .mountNull)
        case .mountMount:
            return .init(rpcReply: rpcReply, nfsReply: .mount(try self.readNFS3ReplyMount()))
        case .mountUnmount:
            return .init(rpcReply: rpcReply, nfsReply: .unmount(try self.readNFS3ReplyUnmount()))
        case .nfsNull:
            return .init(rpcReply: rpcReply, nfsReply: .null)
        case .nfsGetAttr:
            return .init(rpcReply: rpcReply, nfsReply: .getattr(try self.readNFS3ReplyGetAttr()))
        case .nfsFSInfo:
            return .init(rpcReply: rpcReply, nfsReply: .fsinfo(try self.readNFS3ReplyFSInfo()))
        case .nfsPathConf:
            return .init(rpcReply: rpcReply, nfsReply: .pathconf(try self.readNFS3ReplyPathConf()))
        case .nfsFSStat:
            return .init(rpcReply: rpcReply, nfsReply: .fsstat(try self.readNFS3ReplyFSStat()))
        case .nfsAccess:
            return .init(rpcReply: rpcReply, nfsReply: .access(try self.readNFS3ReplyAccess()))
        case .nfsLookup:
            return .init(rpcReply: rpcReply, nfsReply: .lookup(try self.readNFS3ReplyLookup()))
        case .nfsReadDirPlus:
            return .init(rpcReply: rpcReply, nfsReply: .readdirplus(try self.readNFS3ReplyReadDirPlus()))
        case .nfsReadDir:
            return .init(rpcReply: rpcReply, nfsReply: .readdir(try self.readNFS3ReplyReadDir()))
        case .nfsRead:
            return .init(rpcReply: rpcReply, nfsReply: .read(try self.readNFS3ReplyRead()))
        case .nfsReadLink:
            return .init(rpcReply: rpcReply, nfsReply: .readlink(try self.readNFS3ReplyReadlink()))
        case .nfsSetAttr:
            return .init(rpcReply: rpcReply, nfsReply: .setattr(try self.readNFS3ReplySetattr()))
        default:
            throw NFS3Error.unknownProgramOrProcedure(.reply(rpcReply))
        }
    }

    mutating func readNFS3Call(rpc: RPCCall) throws -> RPCNFS3Call {
        switch RPCNFS3ProcedureID(program: rpc.program, procedure: rpc.procedure) {
        case .mountNull:
            return .init(rpcCall: rpc, nfsCall: .mountNull(try self.readMountCallNull()))
        case .mountMount:
            return .init(rpcCall: rpc, nfsCall: .mount(try self.readNFS3CallMount()))
        case .mountUnmount:
            return .init(rpcCall: rpc, nfsCall: .unmount(try self.readNFS3CallUnmount()))
        case .nfsNull:
            return .init(rpcCall: rpc, nfsCall: .null(try self.readNFS3CallNull()))
        case .nfsGetAttr:
            return .init(rpcCall: rpc, nfsCall: .getattr(try self.readNFS3CallGetattr()))
        case .nfsFSInfo:
            return .init(rpcCall: rpc, nfsCall: .fsinfo(try self.readNFS3CallFSInfo()))
        case .nfsPathConf:
            return .init(rpcCall: rpc, nfsCall: .pathconf(try self.readNFS3CallPathConf()))
        case .nfsFSStat:
            return .init(rpcCall: rpc, nfsCall: .fsstat(try self.readNFS3CallFSStat()))
        case .nfsAccess:
            return .init(rpcCall: rpc, nfsCall: .access(try self.readNFS3CallAccess()))
        case .nfsLookup:
            return .init(rpcCall: rpc, nfsCall: .lookup(try self.readNFS3CallLookup()))
        case .nfsReadDirPlus:
            return .init(rpcCall: rpc, nfsCall: .readdirplus(try self.readNFS3CallReadDirPlus()))
        case .nfsReadDir:
            return .init(rpcCall: rpc, nfsCall: .readdir(try self.readNFS3CallReadDir()))
        case .nfsRead:
            return .init(rpcCall: rpc, nfsCall: .read(try self.readNFS3CallRead()))
        case .nfsReadLink:
            return .init(rpcCall: rpc, nfsCall: .readlink(try self.readNFS3CallReadlink()))
        case .nfsSetAttr:
            return .init(rpcCall: rpc, nfsCall: .setattr(try self.readNFS3CallSetattr()))
        default:
            throw NFS3Error.unknownProgramOrProcedure(.call(rpc))
        }
    }

    @discardableResult public mutating func writeRPCNFS3Call(_ rpcNFS3Call: RPCNFS3Call) -> Int {
        let startWriterIndex = self.writerIndex
        self.writeRPCFragmentHeader(.init(length: 12_345_678, last: false))  // placeholder, overwritten later
        self.writeInteger(rpcNFS3Call.rpcCall.xid)

        self.writeRPCCall(rpcNFS3Call.rpcCall)

        switch rpcNFS3Call.nfsCall {
        case .mountNull:
            ()  // noop
        case .mount(let nfsCallMount):
            self.writeNFS3CallMount(nfsCallMount)
        case .unmount(let nfsCallUnmount):
            self.writeNFS3CallUnmount(nfsCallUnmount)
        case .null:
            ()  // noop
        case .getattr(let nfsCallGetAttr):
            self.writeNFS3CallGetattr(nfsCallGetAttr)
        case .fsinfo(let nfsCallFSInfo):
            self.writeNFS3CallFSInfo(nfsCallFSInfo)
        case .pathconf(let nfsCallPathConf):
            self.writeNFS3CallPathConf(nfsCallPathConf)
        case .fsstat(let nfsCallFSStat):
            self.writeNFS3CallFSStat(nfsCallFSStat)
        case .access(let nfsCallAccess):
            self.writeNFS3CallAccess(nfsCallAccess)
        case .lookup(let nfsCallLookup):
            self.writeNFS3CallLookup(nfsCallLookup)
        case .readdirplus(let nfsCallReadDirPlus):
            self.writeNFS3CallReadDirPlus(nfsCallReadDirPlus)
        case .readdir(let nfsCallReadDir):
            self.writeNFS3CallReadDir(nfsCallReadDir)
        case .read(let nfsCallRead):
            self.writeNFS3CallRead(nfsCallRead)
        case .readlink(let nfsCallReadlink):
            self.writeNFS3CallReadlink(nfsCallReadlink)
        case .setattr(let nfsCallSetattr):
            self.writeNFS3CallSetattr(nfsCallSetattr)
        case ._PLEASE_DO_NOT_EXHAUSTIVELY_MATCH_THIS_ENUM_NEW_CASES_MIGHT_BE_ADDED_IN_THE_FUTURE:
            // inside the module, matching exhaustively is okay
            preconditionFailure("unknown NFS3 call, this should never happen. Please report a bug.")
        }

        self.setRPCFragmentHeader(
            .init(
                length: UInt32(self.writerIndex - startWriterIndex - 4),
                last: true
            ),
            at: startWriterIndex
        )
        return self.writerIndex - startWriterIndex
    }

    @discardableResult public mutating func writeRPCNFS3ReplyPartially(
        _ rpcNFS3Reply: RPCNFS3Reply
    ) -> (Int, NFS3PartialWriteNextStep) {
        var nextStep: NFS3PartialWriteNextStep = .doNothing

        let startWriterIndex = self.writerIndex
        self.writeRPCFragmentHeader(.init(length: 12_345_678, last: false))  // placeholder, overwritten later
        self.writeInteger(rpcNFS3Reply.rpcReply.xid)

        self.writeRPCReply(rpcNFS3Reply.rpcReply)

        switch rpcNFS3Reply.nfsReply {
        case .mountNull:
            ()  // noop
        case .mount(let nfsReplyMount):
            self.writeNFS3ReplyMount(nfsReplyMount)
        case .unmount(let nfsReplyUnmount):
            self.writeNFS3ReplyUnmount(nfsReplyUnmount)
        case .null:
            ()  // noop
        case .getattr(let nfsReplyGetAttr):
            self.writeNFS3ReplyGetAttr(nfsReplyGetAttr)
        case .fsinfo(let nfsReplyFSInfo):
            self.writeNFS3ReplyFSInfo(nfsReplyFSInfo)
        case .pathconf(let nfsReplyPathConf):
            self.writeNFS3ReplyPathConf(nfsReplyPathConf)
        case .fsstat(let nfsReplyFSStat):
            self.writeNFS3ReplyFSStat(nfsReplyFSStat)
        case .access(let nfsReplyAccess):
            self.writeNFS3ReplyAccess(nfsReplyAccess)
        case .lookup(let nfsReplyLookup):
            self.writeNFS3ReplyLookup(nfsReplyLookup)
        case .readdirplus(let nfsReplyReadDirPlus):
            self.writeNFS3ReplyReadDirPlus(nfsReplyReadDirPlus)
        case .readdir(let nfsReplyReadDir):
            self.writeNFS3ReplyReadDir(nfsReplyReadDir)
        case .read(let nfsReplyRead):
            nextStep = self.writeNFS3ReplyReadPartially(nfsReplyRead)
        case .readlink(let nfsReplyReadlink):
            self.writeNFS3ReplyReadlink(nfsReplyReadlink)
        case .setattr(let nfsReplySetattr):
            self.writeNFS3ReplySetattr(nfsReplySetattr)
        case ._PLEASE_DO_NOT_EXHAUSTIVELY_MATCH_THIS_ENUM_NEW_CASES_MIGHT_BE_ADDED_IN_THE_FUTURE:
            // inside the module, matching exhaustively is okay
            preconditionFailure("unknown NFS3 reply, this should never happen. Please report a bug.")
        }

        self.setRPCFragmentHeader(
            .init(
                length: UInt32(self.writerIndex - startWriterIndex - 4 + nextStep.bytesToFollow),
                last: true
            ),
            at: startWriterIndex
        )
        return (self.writerIndex - startWriterIndex, nextStep)
    }

    @discardableResult
    public mutating func writeRPCNFS3Reply(_ reply: RPCNFS3Reply) -> Int {
        let (bytesWritten, nextStep) = self.writeRPCNFS3ReplyPartially(reply)
        switch nextStep {
        case .doNothing:
            return bytesWritten
        case .writeBlob(let buffer, numberOfFillBytes: let fillBytes):
            return bytesWritten
                &+ self.writeImmutableBuffer(buffer)
                &+ self.writeRepeatingByte(0x41, count: fillBytes)
        }
    }

    public mutating func readRPCMessage() throws -> (RPCMessage, ByteBuffer)? {
        let save = self
        guard let fragmentHeader = try self.readRPCFragmentHeader(),
            let xid = self.readInteger(as: UInt32.self),
            let messageType = self.readInteger(as: UInt32.self)
        else {
            self = save
            return nil
        }

        if fragmentHeader.length > 1 * 1024 * 1024 {
            throw RPCErrors.tooLong(fragmentHeader, xid: xid, messageType: messageType)
        }

        guard fragmentHeader.length >= 8 else {
            throw RPCErrors.fragementHeaderLengthTooShort(fragmentHeader.length)
        }

        guard var body = self.readSlice(length: Int(fragmentHeader.length - 8)) else {
            self = save
            return nil
        }

        switch RPCMessageType(rawValue: messageType) {
        case .some(.call):
            return (.call(try body.readRPCCall(xid: xid)), body)
        case .some(.reply):
            return (.reply(try body.readRPCReply(xid: xid)), body)
        case .none:
            throw RPCErrors.unknownType(messageType)
        }
    }
}
