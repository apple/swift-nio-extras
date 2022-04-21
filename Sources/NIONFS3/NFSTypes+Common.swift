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

// MARK: - SwiftNFS Specifics
@available(*, deprecated, renamed: "RPCNFS3Call")
public typealias RPCNFSCall = RPCNFS3Call

public struct RPCNFS3Call: Equatable {
    public init(rpcCall: RPCCall, nfsCall: NFS3Call) {
        self.rpcCall = rpcCall
        self.nfsCall = nfsCall
    }

    public init(nfsCall: NFS3Call,
                xid: UInt32,
                credentials: RPCCredentials = .init(flavor: 0, length: 0, otherBytes: ByteBuffer()),
                verifier: RPCOpaqueAuth = RPCOpaqueAuth(flavor: .noAuth)) {
        var rpcCall = RPCCall(xid: xid,
                              rpcVersion: 2,
                              program: .max, // placeholder, overwritten below
                              programVersion: 3,
                              procedure: .max, // placeholder, overwritten below
                              credentials: credentials,
                              verifier: verifier)

        switch nfsCall {
        case .mountNull:
            rpcCall.programAndProcedure = .mountNull
        case .mount:
            rpcCall.programAndProcedure = .mountMount
        case .unmount:
            rpcCall.programAndProcedure = .mountUnmount
        case .null:
            rpcCall.programAndProcedure = .nfsNull
        case .getattr:
            rpcCall.programAndProcedure = .nfsGetAttr
        case .fsinfo:
            rpcCall.programAndProcedure = .nfsFSInfo
        case .pathconf:
            rpcCall.programAndProcedure = .nfsPathConf
        case .fsstat:
            rpcCall.programAndProcedure = .nfsFSStat
        case .access:
            rpcCall.programAndProcedure = .nfsAccess
        case .lookup:
            rpcCall.programAndProcedure = .nfsLookup
        case .readdirplus:
            rpcCall.programAndProcedure = .nfsReadDirPlus
        case .readdir:
            rpcCall.programAndProcedure = .nfsReadDir
        case .read:
            rpcCall.programAndProcedure = .nfsRead
        case .readlink:
            rpcCall.programAndProcedure = .nfsReadLink
        case .setattr:
            rpcCall.programAndProcedure = .nfsSetAttr
        case ._PLEASE_DO_NOT_EXHAUSTIVELY_MATCH_THIS_ENUM_NEW_CASES_MIGHT_BE_ADDED_IN_THE_FUTURE:
            // inside the module, matching exhaustively is okay
            preconditionFailure("unknown NFS3 call, this should never happen. Please report a bug.")
        }

        self = .init(rpcCall: rpcCall, nfsCall: nfsCall)
    }

    public var rpcCall: RPCCall
    public var nfsCall: NFS3Call
}

extension RPCNFS3Call: Identifiable {
    public typealias ID = UInt32

    public var id: ID {
        return self.rpcCall.xid
    }
}

@available(*, deprecated, renamed: "RPCNFS3Reply")
public typealias RPCNFSReply = RPCNFS3Reply

public struct RPCNFS3Reply: Equatable {
    public init(rpcReply: RPCReply, nfsReply: NFS3Reply) {
        self.rpcReply = rpcReply
        self.nfsReply = nfsReply
    }

    public var rpcReply: RPCReply
    public var nfsReply: NFS3Reply
}

extension RPCNFS3Reply: Identifiable {
    public typealias ID = UInt32

    public var id: ID {
        return self.rpcReply.xid
    }
}

public enum NFS3Result<Okay, Fail> {
    case okay(Okay)
    case fail(NFS3Status, Fail)
}

extension NFS3Result: Equatable where Okay: Equatable, Fail: Equatable {
}

extension NFS3Result {
    public var status: NFS3Status {
        switch self {
        case .okay:
            return .ok
        case .fail(let status, _):
            assert(status != .ok)
            return status
        }
    }
}

// MARK: - General
public typealias NFS3FileMode = UInt32
public typealias NFS3UID = UInt32
public typealias NFS3GID = UInt32
public typealias NFS3Size = UInt64
public typealias NFS3SpecData = UInt64
public typealias NFS3FileID = UInt64
public typealias NFS3Cookie = UInt64
public typealias NFS3CookieVerifier = UInt64
public typealias NFS3Offset = UInt64
public typealias NFS3Count = UInt32

public struct NFS3Nothing: Equatable {
    public init() {}
}

public enum NFS3Status: UInt32 {
   case ok = 0
   case errorPERM = 1
   case errorNOENT       = 2
   case errorIO          = 5
   case errorNXIO        = 6
   case errorACCES       = 13
   case errorEXIST       = 17
   case errorXDEV        = 18
   case errorNODEV       = 19
   case errorNOTDIR      = 20
   case errorISDIR       = 21
   case errorINVAL       = 22
   case errorFBIG        = 27
   case errorNOSPC       = 28
   case errorROFS        = 30
   case errorMLINK       = 31
   case errorNAMETOOLONG = 63
   case errorNOTEMPTY    = 66
   case errorDQUOT       = 69
   case errorSTALE       = 70
   case errorREMOTE      = 71
   case errorBADHANDLE   = 10001
   case errorNOT_SYNC    = 10002
   case errorBAD_COOKIE  = 10003
   case errorNOTSUPP     = 10004
   case errorTOOSMALL    = 10005
   case errorSERVERFAULT = 10006
   case errorBADTYPE     = 10007
   case errorJUKEBOX     = 10008
}

public struct NFS3Access: OptionSet {
    public typealias RawValue = UInt32

    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let read: NFS3Access = .init(rawValue: 0x0001)
    public static let lookup: NFS3Access = .init(rawValue: 0x0002)
    public static let modify: NFS3Access = .init(rawValue: 0x0004)
    public static let extend: NFS3Access = .init(rawValue: 0x0008)
    public static let delete: NFS3Access = .init(rawValue: 0x0010)
    public static let execute: NFS3Access = .init(rawValue: 0x0020)

    public static let all: NFS3Access = [.read, .lookup, .modify, .extend, .delete, .execute]
    public static let allReadOnly: NFS3Access = [.read, .lookup, .execute]
}

public enum NFS3FileType: UInt32 {
    case regular = 1
    case directory = 2
    case blockDevice = 3
    case characterDevice = 4
    case link = 5
    case socket = 6
    case fifo = 7
}

public typealias NFS3Bool = Bool

public struct NFS3FileHandle: Hashable, CustomStringConvertible {
    @usableFromInline
    internal var _value: UInt64

    public init(_ value: UInt64) {
        self._value = value
    }

    public init(_ bytes: ByteBuffer) {
        precondition(bytes.readableBytes <= 64, "NFS3 mandates that file handles are NFS3_FHSIZE (64) bytes or less.")
        precondition(bytes.readableBytes == MemoryLayout<UInt64>.size,
                     "Sorry, at the moment only file handles with exactly 8 bytes are implemented.")
        var bytes = bytes
        self = NFS3FileHandle(bytes.readInteger(endianness: .big, as: UInt64.self)!)
    }

    public var description: String {
        return "NFS3FileHandle(\(self._value))"
    }
}

extension UInt64 {
    // This initialiser is fallible because we're only _currently_ require that all file handles be exactly 8 bytes
    // long. This limitation should be removed in the future.
    @inlinable
    public init?(_ fileHandle: NFS3FileHandle) {
        self = fileHandle._value
    }
}

extension UInt32 {
    @inlinable
    public init?(_ fileHandle: NFS3FileHandle) {
        if let value = UInt32(exactly: fileHandle._value) {
            self = value
        } else {
            return nil
        }
    }
}


public struct NFS3Time: Equatable {
    public init(seconds: UInt32, nanoSeconds: UInt32) {
        self.seconds = seconds
        self.nanoSeconds = nanoSeconds
    }

    public var seconds: UInt32
    public var nanoSeconds: UInt32
}

public struct NFS3FileAttr: Equatable {
    public init(type: NFS3FileType, mode: NFS3FileMode, nlink: UInt32, uid: NFS3UID, gid: NFS3GID, size: NFS3Size, used: NFS3Size, rdev: NFS3SpecData, fsid: UInt64, fileid: NFS3FileID, atime: NFS3Time, mtime: NFS3Time, ctime: NFS3Time) {
        self.type = type
        self.mode = mode
        self.nlink = nlink
        self.uid = uid
        self.gid = gid
        self.size = size
        self.used = used
        self.rdev = rdev
        self.fsid = fsid
        self.fileid = fileid
        self.atime = atime
        self.mtime = mtime
        self.ctime = ctime
    }

    public var type: NFS3FileType
    public var mode: NFS3FileMode
    public var nlink: UInt32
    public var uid: NFS3UID
    public var gid: NFS3GID
    public var size: NFS3Size
    public var used: NFS3Size
    public var rdev: NFS3SpecData
    public var fsid: UInt64
    public var fileid: NFS3FileID
    public var atime: NFS3Time
    public var mtime: NFS3Time
    public var ctime: NFS3Time
}

public struct NFS3WeakCacheConsistencyAttr: Equatable {
    public init(size: NFS3Size, mtime: NFS3Time, ctime: NFS3Time) {
        self.size = size
        self.mtime = mtime
        self.ctime = ctime
    }

    public var size: NFS3Size
    public var mtime: NFS3Time
    public var ctime: NFS3Time
}

public struct NFS3WeakCacheConsistencyData: Equatable {
    public init(before: NFS3WeakCacheConsistencyAttr? = nil, after: NFS3FileAttr? = nil) {
        self.before = before
        self.after = after
    }

    public var before: NFS3WeakCacheConsistencyAttr?
    public var after: NFS3FileAttr?
}

extension ByteBuffer {
    public mutating func readNFSWeakCacheConsistencyAttr() throws -> NFS3WeakCacheConsistencyAttr {
        let size = try self.readNFSInteger(as: NFS3Size.self)
        let mtime = try self.readNFSTime()
        let ctime = try self.readNFSTime()

        return .init(size: size, mtime: mtime, ctime: ctime)
    }

    public mutating func writeNFSWeakCacheConsistencyAttr(_ wccAttr: NFS3WeakCacheConsistencyAttr) {
        self.writeInteger(wccAttr.size, endianness: .big)
        self.writeNFSTime(wccAttr.mtime)
        self.writeNFSTime(wccAttr.ctime)
    }

    public mutating func readNFSWeakCacheConsistencyData() throws -> NFS3WeakCacheConsistencyData {
        let before = try self.readNFSOptional { try $0.readNFSWeakCacheConsistencyAttr() }
        let after = try self.readNFSOptional { try $0.readNFSFileAttr() }

        return .init(before: before, after: after)
    }

    public mutating func writeNFSWeakCacheConsistencyData(_ wccData: NFS3WeakCacheConsistencyData) {
        self.writeNFSOptional(wccData.before, writer: { $0.writeNFSWeakCacheConsistencyAttr($1) })
        self.writeNFSOptional(wccData.after, writer: { $0.writeNFSFileAttr($1) })
    }

    public mutating func readNFSInteger<I: FixedWidthInteger>(as: I.Type = I.self) throws -> I {
        if let value = self.readInteger(endianness: .big, as: I.self) {
            return value
        } else {
            throw NFS3Error.illegalRPCTooShort
        }
    }

    public mutating func readNFSBlob() throws -> ByteBuffer {
        let length = try self.readNFSInteger(as: UInt32.self)
        guard let blob = self.readSlice(length: Int(length)),
              let _ = self.readSlice(length: nfsStringFillBytes(Int(length))) else {
                  throw NFS3Error.illegalRPCTooShort
              }
        return blob
    }

    public mutating func writeNFSBlob(_ blob: ByteBuffer) {
        let byteCount = blob.readableBytes
        self.writeInteger(UInt32(byteCount), endianness: .big)
        self.writeImmutableBuffer(blob)
        self.writeRepeatingByte(0x42, count: nfsStringFillBytes(byteCount))
    }

    public mutating func readNFSString() throws -> String {
        let blob = try self.readNFSBlob()
        return String(buffer: blob)
    }

    public mutating func writeNFSString(_ string: String) {
        let byteCount = string.utf8.count
        self.writeInteger(UInt32(byteCount), endianness: .big)
        self.writeString(string)
        self.writeRepeatingByte(0x42, count: nfsStringFillBytes(byteCount))
    }

    public mutating func readNFSFileHandle() throws -> NFS3FileHandle {
        guard let values = self.readMultipleIntegers(endianness: .big, as: (UInt32, UInt64).self) else {
            throw NFS3Error.illegalRPCTooShort
        }
        let length = values.0
        let id = values.1

        // TODO: This is a temporary limitation to be lifted later.
        guard length == MemoryLayout<UInt64>.size else {
            throw NFS3Error.invalidFileHandleFormat(length: length)
        }
        return NFS3FileHandle(id)
    }

    public mutating func writeNFSFileHandle(_ fileHandle: NFS3FileHandle) {
        // TODO: This ! is safe at the moment until the file handle == 64 bits limitation is lifted
        let id = UInt64(fileHandle)!
        self.writeMultipleIntegers(UInt32(MemoryLayout.size(ofValue: id)), id, endianness: .big)
    }

    public mutating func writeNFSFileType(_ fileType: NFS3FileType) {
        self.writeInteger(fileType.rawValue, endianness: .big)
    }

    public mutating func writeNFSTime(_ time: NFS3Time) {
        self.writeMultipleIntegers(time.seconds, time.nanoSeconds, endianness: .big)
    }

    public mutating func read3NFSTimes() throws -> (NFS3Time, NFS3Time, NFS3Time) {
        guard let values = self.readMultipleIntegers(endianness: .big,
                                                      as: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32).self) else {
            throw NFS3Error.illegalRPCTooShort
        }
        return (NFS3Time(seconds: values.0, nanoSeconds: values.1),
                NFS3Time(seconds: values.2, nanoSeconds: values.3),
                NFS3Time(seconds: values.4, nanoSeconds: values.5))
    }

    public mutating func write3NFSTimes(_ time1: NFS3Time, _ time2: NFS3Time, _ time3: NFS3Time) {
        self.writeMultipleIntegers(time1.seconds, time1.nanoSeconds,
                                   time2.seconds, time2.nanoSeconds,
                                   time3.seconds, time3.nanoSeconds)
    }

    public mutating func readNFSTime() throws -> NFS3Time {
        guard let values = self.readMultipleIntegers(endianness: .big, as: (UInt32, UInt32).self) else {
            throw NFS3Error.illegalRPCTooShort
        }

        return .init(seconds: values.0, nanoSeconds: values.1)
    }

    public mutating func readNFSFileType() throws -> NFS3FileType {
        let typeRaw = try self.readNFSInteger(as: UInt32.self)
        if let type = NFS3FileType(rawValue: typeRaw) {
            return type
        } else {
            throw NFS3Error.invalidFileType(typeRaw)
        }
    }

    public mutating func readNFSFileAttr() throws -> NFS3FileAttr {
        let type = try self.readNFSFileType()
        guard let values = self.readMultipleIntegers(endianness: .big,
                                                      as: (UInt32, UInt32, UInt32, UInt32, NFS3Size,
                                                           NFS3Size, UInt64, UInt64, NFS3FileID,
                                                           UInt32, UInt32, UInt32, UInt32, UInt32, UInt32).self) else {
            throw NFS3Error.illegalRPCTooShort
        }
        let mode = values.0
        let nlink = values.1
        let uid = values.2
        let gid = values.3
        let size = values.4
        let used = values.5
        let rdev = values.6
        let fsid = values.7
        let fileid = values.8
        let atime = NFS3Time(seconds: values.9, nanoSeconds: values.10)
        let mtime = NFS3Time(seconds: values.11, nanoSeconds: values.12)
        let ctime = NFS3Time(seconds: values.13, nanoSeconds: values.14)

        return .init(type: type, mode: mode, nlink: nlink,
                     uid: uid, gid: gid,
                     size: size, used: used,
                     rdev: rdev, fsid: fsid, fileid: fileid,
                     atime: atime, mtime: mtime, ctime: ctime)
    }

    public mutating func writeNFSFileAttr(_ attributes: NFS3FileAttr) {
        self.writeNFSFileType(attributes.type)
        self.writeMultipleIntegers(
            attributes.mode,
            attributes.nlink,
            attributes.uid,
            attributes.gid,
            attributes.size,
            attributes.used,
            attributes.rdev,
            attributes.fsid,
            attributes.fileid,
            attributes.atime.seconds,
            attributes.atime.nanoSeconds,
            attributes.mtime.seconds,
            attributes.mtime.nanoSeconds,
            attributes.ctime.seconds,
            attributes.ctime.nanoSeconds,
            endianness: .big)
    }

    public mutating func writeNFSBool(_ bool: NFS3Bool) {
        self.writeInteger(bool == true ? 1 : 0, endianness: .big, as: UInt32.self)
    }

    public mutating func readNFSBool() throws -> Bool {
        let rawValue = try self.readNFSInteger(as: UInt32.self)
        return rawValue != 0
    }

    public mutating func readNFSOptional<T>(_ reader: (inout ByteBuffer) throws -> T) rethrows -> T? {
        if self.readInteger(endianness: .big, as: UInt32.self) == 1 {
            return try reader(&self)
        } else {
            return nil
        }
    }

    public mutating func writeNFSOptional<T>(_ value: T?, writer: (inout ByteBuffer, T) -> Void) {
        if let value = value {
            self.writeInteger(1, endianness: .big, as: UInt32.self)
            writer(&self, value)
        } else {
            self.writeInteger(0, endianness: .big, as: UInt32.self)
        }
    }

    public mutating func readNFSCount() throws -> NFS3Count {
        return try self.readNFSInteger(as: NFS3Count.self)
    }

    public mutating func readNFSList<Element>(readEntry: (inout ByteBuffer) throws -> Element) throws -> [Element] {
        let count = try self.readNFSCount()
        var result: [Element] = []
        result.reserveCapacity(Int(count))

        for _ in 0..<count {
            result.append(try readEntry(&self))
        }

        return result
    }

    public mutating func writeNFSCookieVerifier(_ verifier: NFS3CookieVerifier) {
        self.writeInteger(verifier, endianness: .big)
    }

    public mutating func writeNFSCookie(_ cookie: NFS3Cookie) {
        self.writeInteger(cookie, endianness: .big)
    }

    public mutating func writeNFSFileID(_ fileID: NFS3FileID) {
        self.writeInteger(fileID, endianness: .big)
    }

    public mutating func writeNFSResultStatus<O, F>(_ result: NFS3Result<O, F>) {
        self.writeInteger(result.status.rawValue, endianness: .big, as: UInt32.self)
    }

    public mutating func readNFSStatus() throws -> NFS3Status {
        let rawValue = try self.readNFSInteger(as: UInt32.self)
        if let status = NFS3Status(rawValue: rawValue) {
            return status
        } else {
            throw NFS3Error.invalidStatus(rawValue)
        }
    }

    public mutating func readRPCAuthFlavor() throws -> RPCAuthFlavor {
        let rawValue = try self.readNFSInteger(as: UInt32.self)
        if let flavor = RPCAuthFlavor(rawValue: rawValue) {
            return flavor
        } else {
            throw RPCErrors.invalidAuthFlavor(rawValue)
        }
    }

    public mutating func readNFSResult<O, F>(readOkay: (inout ByteBuffer) throws -> O,
                                             readFail: (inout ByteBuffer) throws -> F) throws -> NFS3Result<O, F> {
        let status = try self.readNFSStatus()
        switch status {
        case .ok:
            return .okay(try readOkay(&self))
        default:
            return .fail(status, try readFail(&self))
        }
    }

    public mutating func writeNFSSize(_ size: NFS3Size) {
        self.writeInteger(size, endianness: .big)
    }

    public mutating func readNFSSize() throws -> NFS3Size {
        return try self.readNFSInteger()
    }
}

public enum NFS3PartialWriteNextStep {
    case doNothing
    case writeBlob(ByteBuffer, numberOfFillBytes: Int)
}

extension NFS3PartialWriteNextStep {
    var bytesToFollow: Int {
        switch self {
        case .doNothing:
            return 0
        case .writeBlob(let bytes, numberOfFillBytes: let fillBytes):
            return bytes.readableBytes &+ fillBytes
        }
    }
}
