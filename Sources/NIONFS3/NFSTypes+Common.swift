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

// MARK: - NIONFS3 Specifics
public struct RPCNFS3Call: Hashable & Sendable {
    public init(rpcCall: RPCCall, nfsCall: NFS3Call) {
        self.rpcCall = rpcCall
        self.nfsCall = nfsCall
    }

    public init(
        nfsCall: NFS3Call,
        xid: UInt32,
        credentials: RPCCredentials = .init(flavor: 0, length: 0, otherBytes: ByteBuffer()),
        verifier: RPCOpaqueAuth = RPCOpaqueAuth(flavor: .noAuth)
    ) {
        var rpcCall = RPCCall(
            xid: xid,
            rpcVersion: 2,
            program: .max,  // placeholder, overwritten below
            programVersion: 3,
            procedure: .max,  // placeholder, overwritten below
            credentials: credentials,
            verifier: verifier
        )

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
        self.rpcCall.xid
    }
}

public struct RPCNFS3Reply: Hashable & Sendable {
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
        self.rpcReply.xid
    }
}

public enum NFS3Result<Okay, Fail> {
    case okay(Okay)
    case fail(NFS3Status, Fail)
}

extension NFS3Result: Hashable where Okay: Hashable, Fail: Hashable {
}

extension NFS3Result: Equatable where Okay: Equatable, Fail: Equatable {
}

extension NFS3Result: Sendable where Okay: Sendable, Fail: Sendable {
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
public struct NFS3FileMode: Hashable & Sendable {
    public typealias RawValue = UInt32

    public var rawValue: RawValue

    public init(rawValue: NFS3FileMode.RawValue) {
        self.rawValue = rawValue
    }
}

extension NFS3FileMode: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = RawValue

    public init(integerLiteral value: RawValue) {
        self = .init(rawValue: value)
    }
}

extension ByteBuffer {
    public mutating func readNFS3FileMode() throws -> NFS3FileMode {
        NFS3FileMode(rawValue: try self.readNFS3Integer(as: NFS3FileMode.RawValue.self))
    }

    @discardableResult
    public mutating func writeNFS3FileMode(_ value: NFS3FileMode) -> Int {
        self.writeInteger(value.rawValue)
    }
}

public struct NFS3UID: Hashable & Sendable {
    public typealias RawValue = UInt32

    public var rawValue: RawValue

    public init(rawValue: NFS3UID.RawValue) {
        self.rawValue = rawValue
    }
}

extension NFS3UID: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = RawValue

    public init(integerLiteral value: RawValue) {
        self = .init(rawValue: value)
    }
}

extension ByteBuffer {
    public mutating func readNFS3UID() throws -> NFS3UID {
        NFS3UID(rawValue: try self.readNFS3Integer(as: NFS3UID.RawValue.self))
    }

    @discardableResult
    public mutating func writeNFS3UID(_ value: NFS3UID) -> Int {
        self.writeInteger(value.rawValue)
    }
}

public struct NFS3GID: Hashable & Sendable {
    public typealias RawValue = UInt32

    public var rawValue: RawValue

    public init(rawValue: NFS3GID.RawValue) {
        self.rawValue = rawValue
    }
}

extension NFS3GID: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = RawValue

    public init(integerLiteral value: RawValue) {
        self = .init(rawValue: value)
    }
}

extension ByteBuffer {
    public mutating func readNFS3GID() throws -> NFS3GID {
        NFS3GID(rawValue: try self.readNFS3Integer(as: NFS3GID.RawValue.self))
    }

    @discardableResult
    public mutating func writeNFS3GID(_ value: NFS3GID) -> Int {
        self.writeInteger(value.rawValue)
    }
}

public struct NFS3Size: Hashable & Sendable {
    public typealias RawValue = UInt64

    public var rawValue: RawValue

    public init(rawValue: NFS3Size.RawValue) {
        self.rawValue = rawValue
    }
}

extension NFS3Size: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = RawValue

    public init(integerLiteral value: RawValue) {
        self = .init(rawValue: value)
    }
}

extension ByteBuffer {
    public mutating func readNFS3Size() throws -> NFS3Size {
        NFS3Size(rawValue: try self.readNFS3Integer(as: NFS3Size.RawValue.self))
    }

    @discardableResult
    public mutating func writeNFS3Size(_ value: NFS3Size) -> Int {
        self.writeInteger(value.rawValue)
    }
}

public struct NFS3SpecData: Hashable & Sendable {
    public typealias RawValue = UInt64

    public var rawValue: RawValue

    public init(rawValue: NFS3SpecData.RawValue) {
        self.rawValue = rawValue
    }
}

extension NFS3SpecData: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = RawValue

    public init(integerLiteral value: RawValue) {
        self = .init(rawValue: value)
    }
}

extension ByteBuffer {
    public mutating func readNFS3SpecData() throws -> NFS3SpecData {
        NFS3SpecData(rawValue: try self.readNFS3Integer(as: NFS3SpecData.RawValue.self))
    }

    @discardableResult
    public mutating func writeNFS3SpecData(_ value: NFS3SpecData) -> Int {
        self.writeInteger(value.rawValue)
    }
}

public struct NFS3FileID: Hashable & Sendable {
    public typealias RawValue = UInt64

    public var rawValue: RawValue

    public init(rawValue: NFS3FileID.RawValue) {
        self.rawValue = rawValue
    }
}

extension NFS3FileID: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = RawValue

    public init(integerLiteral value: RawValue) {
        self = .init(rawValue: value)
    }
}

extension ByteBuffer {
    public mutating func readNFS3FileID() throws -> NFS3FileID {
        NFS3FileID(rawValue: try self.readNFS3Integer(as: NFS3FileID.RawValue.self))
    }

    @discardableResult
    public mutating func writeNFS3FileID(_ value: NFS3FileID) -> Int {
        self.writeInteger(value.rawValue)
    }
}

public struct NFS3Cookie: Hashable & Sendable {
    public typealias RawValue = UInt64

    public var rawValue: RawValue

    public init(rawValue: NFS3Cookie.RawValue) {
        self.rawValue = rawValue
    }
}

extension NFS3Cookie: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = RawValue

    public init(integerLiteral value: RawValue) {
        self = .init(rawValue: value)
    }
}

extension ByteBuffer {
    public mutating func readNFS3Cookie() throws -> NFS3Cookie {
        NFS3Cookie(rawValue: try self.readNFS3Integer(as: NFS3Cookie.RawValue.self))
    }

    @discardableResult
    public mutating func writeNFS3Cookie(_ value: NFS3Cookie) -> Int {
        self.writeInteger(value.rawValue)
    }
}

public struct NFS3CookieVerifier: Hashable & Sendable {
    public typealias RawValue = UInt64

    public var rawValue: RawValue

    public init(rawValue: NFS3CookieVerifier.RawValue) {
        self.rawValue = rawValue
    }
}

extension NFS3CookieVerifier: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = RawValue

    public init(integerLiteral value: RawValue) {
        self = .init(rawValue: value)
    }
}

extension ByteBuffer {
    public mutating func readNFS3CookieVerifier() throws -> NFS3CookieVerifier {
        NFS3CookieVerifier(rawValue: try self.readNFS3Integer(as: NFS3CookieVerifier.RawValue.self))
    }

    @discardableResult
    public mutating func writeNFS3CookieVerifier(_ value: NFS3CookieVerifier) -> Int {
        self.writeInteger(value.rawValue)
    }
}

public struct NFS3Offset: Hashable & Sendable {
    public typealias RawValue = UInt64

    public var rawValue: RawValue

    public init(rawValue: NFS3Offset.RawValue) {
        self.rawValue = rawValue
    }
}

extension NFS3Offset: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = RawValue

    public init(integerLiteral value: RawValue) {
        self = .init(rawValue: value)
    }
}

extension ByteBuffer {
    public mutating func readNFS3Offset() throws -> NFS3Offset {
        NFS3Offset(rawValue: try self.readNFS3Integer(as: NFS3Offset.RawValue.self))
    }

    @discardableResult
    public mutating func writeNFS3Offset(_ value: NFS3Offset) -> Int {
        self.writeInteger(value.rawValue)
    }
}

public struct NFS3Count: Hashable & Sendable {
    public typealias RawValue = UInt32

    public var rawValue: RawValue

    public init(rawValue: NFS3Count.RawValue) {
        self.rawValue = rawValue
    }
}

extension NFS3Count: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = RawValue

    public init(integerLiteral value: RawValue) {
        self = .init(rawValue: value)
    }
}

extension ByteBuffer {
    public mutating func readNFS3Count() throws -> NFS3Count {
        NFS3Count(rawValue: try self.readNFS3Integer(as: NFS3Count.RawValue.self))
    }

    @discardableResult
    public mutating func writeNFS3Count(_ value: NFS3Count) -> Int {
        self.writeInteger(value.rawValue)
    }
}

public struct NFS3Nothing: Hashable & Sendable {
    public init() {}
}

/// The status of an NFS3 operation.
///
/// - seealso: https://www.rfc-editor.org/rfc/rfc1813#page-16
public enum NFS3Status: UInt32, Sendable {
    case ok = 0
    case errorPERM = 1
    case errorNOENT = 2
    case errorIO = 5
    case errorNXIO = 6
    case errorACCES = 13
    case errorEXIST = 17
    case errorXDEV = 18
    case errorNODEV = 19
    case errorNOTDIR = 20
    case errorISDIR = 21
    case errorINVAL = 22
    case errorFBIG = 27
    case errorNOSPC = 28
    case errorROFS = 30
    case errorMLINK = 31
    case errorNAMETOOLONG = 63
    case errorNOTEMPTY = 66
    case errorDQUOT = 69
    case errorSTALE = 70
    case errorREMOTE = 71
    case errorBADHANDLE = 10001
    case errorNOT_SYNC = 10002
    case errorBAD_COOKIE = 10003
    case errorNOTSUPP = 10004
    case errorTOOSMALL = 10005
    case errorSERVERFAULT = 10006
    case errorBADTYPE = 10007
    case errorJUKEBOX = 10008
}

/// Check the access rights to a file.
///
/// - seealso: https://www.rfc-editor.org/rfc/rfc1813#page-40
public struct NFS3Access: OptionSet & Hashable & Sendable {
    public typealias RawValue = UInt32

    public var rawValue: RawValue

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

extension ByteBuffer {
    public mutating func readNFS3Access() throws -> NFS3Access {
        NFS3Access(rawValue: try self.readNFS3Integer(as: UInt32.self))
    }

    public mutating func writeNFS3Access(_ access: NFS3Access) {
        self.writeInteger(access.rawValue)
    }
}

/// The filetype as defined in NFS3.
///
/// - seealso: https://www.rfc-editor.org/rfc/rfc1813#page-20
public enum NFS3FileType: UInt32, Sendable {
    case regular = 1
    case directory = 2
    case blockDevice = 3
    case characterDevice = 4
    case link = 5
    case socket = 6
    case fifo = 7
}

public typealias NFS3Bool = Bool

public struct NFS3FileHandle: Hashable & Sendable & CustomStringConvertible {
    @usableFromInline
    internal var _value: UInt64

    public init(_ value: UInt64) {
        self._value = value
    }

    /// Initialize an ``NFS3FileHandle`` with the raw representation.
    ///
    /// The spec requires the representation to take up 64 bytes or fewer.
    ///
    /// - seealso: https://www.rfc-editor.org/rfc/rfc1813#page-106
    public init(_ bytes: ByteBuffer) {
        precondition(bytes.readableBytes <= 64, "NFS3 mandates that file handles are NFS3_FHSIZE (64) bytes or less.")
        precondition(
            bytes.readableBytes == MemoryLayout<UInt64>.size,
            "Sorry, at the moment only file handles with exactly 8 bytes are implemented."
        )
        var bytes = bytes
        self = NFS3FileHandle(bytes.readInteger(as: UInt64.self)!)
    }

    public var description: String {
        "NFS3FileHandle(\(self._value))"
    }
}

extension UInt64 {
    // This initialiser is fallible because we only _currently_ require that all file handles be exactly 8 bytes
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

public struct NFS3Time: Hashable & Sendable {
    public init(seconds: UInt32, nanoseconds: UInt32) {
        self.seconds = seconds
        self.nanoseconds = nanoseconds
    }

    public var seconds: UInt32
    public var nanoseconds: UInt32
}

public struct NFS3FileAttr: Hashable & Sendable {
    public init(
        type: NFS3FileType,
        mode: NFS3FileMode,
        nlink: UInt32,
        uid: NFS3UID,
        gid: NFS3GID,
        size: NFS3Size,
        used: NFS3Size,
        rdev: NFS3SpecData,
        fsid: UInt64,
        fileid: NFS3FileID,
        atime: NFS3Time,
        mtime: NFS3Time,
        ctime: NFS3Time
    ) {
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

public struct NFS3WeakCacheConsistencyAttr: Hashable & Sendable {
    public init(size: NFS3Size, mtime: NFS3Time, ctime: NFS3Time) {
        self.size = size
        self.mtime = mtime
        self.ctime = ctime
    }

    public var size: NFS3Size
    public var mtime: NFS3Time
    public var ctime: NFS3Time
}

public struct NFS3WeakCacheConsistencyData: Hashable & Sendable {
    public init(before: NFS3WeakCacheConsistencyAttr? = nil, after: NFS3FileAttr? = nil) {
        self.before = before
        self.after = after
    }

    public var before: NFS3WeakCacheConsistencyAttr?
    public var after: NFS3FileAttr?
}

extension ByteBuffer {
    public mutating func readNFS3WeakCacheConsistencyAttr() throws -> NFS3WeakCacheConsistencyAttr {
        let size = try self.readNFS3Size()
        let mtime = try self.readNFS3Time()
        let ctime = try self.readNFS3Time()

        return .init(size: size, mtime: mtime, ctime: ctime)
    }

    @discardableResult public mutating func writeNFS3WeakCacheConsistencyAttr(
        _ wccAttr: NFS3WeakCacheConsistencyAttr
    ) -> Int {
        self.writeNFS3Size(wccAttr.size)
            + self.writeNFS3Time(wccAttr.mtime)
            + self.writeNFS3Time(wccAttr.ctime)
    }

    public mutating func readNFS3WeakCacheConsistencyData() throws -> NFS3WeakCacheConsistencyData {
        let before = try self.readNFS3Optional { try $0.readNFS3WeakCacheConsistencyAttr() }
        let after = try self.readNFS3Optional { try $0.readNFS3FileAttr() }

        return .init(before: before, after: after)
    }

    @discardableResult public mutating func writeNFS3WeakCacheConsistencyData(
        _ wccData: NFS3WeakCacheConsistencyData
    ) -> Int {
        self.writeNFS3Optional(wccData.before, writer: { $0.writeNFS3WeakCacheConsistencyAttr($1) })
            + self.writeNFS3Optional(wccData.after, writer: { $0.writeNFS3FileAttr($1) })
    }

    public mutating func readNFS3Integer<I: FixedWidthInteger>(as: I.Type = I.self) throws -> I {
        if let value = self.readInteger(as: I.self) {
            return value
        } else {
            throw NFS3Error.illegalRPCTooShort
        }
    }

    public mutating func readNFS3Blob() throws -> ByteBuffer {
        let length = try self.readNFS3Integer(as: UInt32.self)
        guard let blob = self.readSlice(length: Int(length)),
            let _ = self.readSlice(length: nfsStringFillBytes(Int(length)))
        else {
            throw NFS3Error.illegalRPCTooShort
        }
        return blob
    }

    @discardableResult public mutating func writeNFS3Blob(_ blob: ByteBuffer) -> Int {
        let byteCount = blob.readableBytes
        return self.writeInteger(UInt32(byteCount))
            + self.writeImmutableBuffer(blob)
            + self.writeRepeatingByte(0x42, count: nfsStringFillBytes(byteCount))
    }

    public mutating func readNFS3String() throws -> String {
        let blob = try self.readNFS3Blob()
        return String(buffer: blob)
    }

    @discardableResult public mutating func writeNFS3String(_ string: String) -> Int {
        let byteCount = string.utf8.count
        return self.writeInteger(UInt32(byteCount))
            + self.writeString(string)
            + self.writeRepeatingByte(0x42, count: nfsStringFillBytes(byteCount))
    }

    public mutating func readNFS3FileHandle() throws -> NFS3FileHandle {
        guard let values = self.readMultipleIntegers(as: (UInt32, UInt64).self) else {
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

    @discardableResult public mutating func writeNFS3FileHandle(_ fileHandle: NFS3FileHandle) -> Int {
        // TODO: This ! is safe at the moment until the file handle == 64 bits limitation is lifted
        let id = UInt64(fileHandle)!
        return self.writeMultipleIntegers(UInt32(MemoryLayout.size(ofValue: id)), id)
    }

    @discardableResult public mutating func writeNFS3FileType(_ fileType: NFS3FileType) -> Int {
        self.writeInteger(fileType.rawValue)
    }

    @discardableResult public mutating func writeNFS3Time(_ time: NFS3Time) -> Int {
        self.writeMultipleIntegers(time.seconds, time.nanoseconds)
    }

    public mutating func read3NFS3Times() throws -> (NFS3Time, NFS3Time, NFS3Time) {
        guard let values = self.readMultipleIntegers(as: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32).self) else {
            throw NFS3Error.illegalRPCTooShort
        }
        return (
            NFS3Time(seconds: values.0, nanoseconds: values.1),
            NFS3Time(seconds: values.2, nanoseconds: values.3),
            NFS3Time(seconds: values.4, nanoseconds: values.5)
        )
    }

    @discardableResult public mutating func write3NFS3Times(
        _ time1: NFS3Time,
        _ time2: NFS3Time,
        _ time3: NFS3Time
    ) -> Int {
        self.writeMultipleIntegers(
            time1.seconds,
            time1.nanoseconds,
            time2.seconds,
            time2.nanoseconds,
            time3.seconds,
            time3.nanoseconds
        )
    }

    public mutating func readNFS3Time() throws -> NFS3Time {
        guard let values = self.readMultipleIntegers(as: (UInt32, UInt32).self) else {
            throw NFS3Error.illegalRPCTooShort
        }

        return .init(seconds: values.0, nanoseconds: values.1)
    }

    public mutating func readNFS3FileType() throws -> NFS3FileType {
        let typeRaw = try self.readNFS3Integer(as: UInt32.self)
        if let type = NFS3FileType(rawValue: typeRaw) {
            return type
        } else {
            throw NFS3Error.invalidFileType(typeRaw)
        }
    }

    public mutating func readNFS3FileAttr() throws -> NFS3FileAttr {
        let type = try self.readNFS3FileType()
        guard
            let values = self.readMultipleIntegers(
                as: (
                    UInt32, UInt32, UInt32, UInt32, NFS3Size.RawValue,
                    NFS3Size.RawValue, UInt64, UInt64, NFS3FileID.RawValue,
                    UInt32, UInt32, UInt32, UInt32, UInt32, UInt32
                ).self
            )
        else {
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
        let atime = NFS3Time(seconds: values.9, nanoseconds: values.10)
        let mtime = NFS3Time(seconds: values.11, nanoseconds: values.12)
        let ctime = NFS3Time(seconds: values.13, nanoseconds: values.14)

        return .init(
            type: type,
            mode: NFS3FileMode(rawValue: mode),
            nlink: nlink,
            uid: NFS3UID(rawValue: uid),
            gid: NFS3GID(rawValue: gid),
            size: NFS3Size(rawValue: size),
            used: NFS3Size(rawValue: used),
            rdev: NFS3SpecData(rawValue: rdev),
            fsid: fsid,
            fileid: NFS3FileID(rawValue: fileid),
            atime: atime,
            mtime: mtime,
            ctime: ctime
        )
    }

    @discardableResult public mutating func writeNFS3FileAttr(_ attributes: NFS3FileAttr) -> Int {
        self.writeNFS3FileType(attributes.type)
            + self.writeMultipleIntegers(
                attributes.mode.rawValue,
                attributes.nlink,
                attributes.uid.rawValue,
                attributes.gid.rawValue,
                attributes.size.rawValue,
                attributes.used.rawValue,
                attributes.rdev.rawValue,
                attributes.fsid,
                attributes.fileid.rawValue,
                attributes.atime.seconds,
                attributes.atime.nanoseconds,
                attributes.mtime.seconds,
                attributes.mtime.nanoseconds,
                attributes.ctime.seconds,
                attributes.ctime.nanoseconds
            )
    }

    @discardableResult public mutating func writeNFS3Bool(_ bool: NFS3Bool) -> Int {
        self.writeInteger(bool == true ? 1 : 0, as: UInt32.self)
    }

    public mutating func readNFS3Bool() throws -> Bool {
        let rawValue = try self.readNFS3Integer(as: UInt32.self)
        return rawValue != 0
    }

    public mutating func readNFS3Optional<T>(_ reader: (inout ByteBuffer) throws -> T) rethrows -> T? {
        if self.readInteger(as: UInt32.self) == 1 {
            return try reader(&self)
        } else {
            return nil
        }
    }

    @discardableResult public mutating func writeNFS3Optional<T>(
        _ value: T?,
        writer: (inout ByteBuffer, T) -> Int
    ) -> Int {
        if let value = value {
            return self.writeInteger(1, as: UInt32.self)
                + writer(&self, value)
        } else {
            return self.writeInteger(0, as: UInt32.self)
        }
    }

    public mutating func readNFS3List<Element>(readEntry: (inout ByteBuffer) throws -> Element) throws -> [Element] {
        let count = try self.readNFS3Count().rawValue
        var result: [Element] = []
        result.reserveCapacity(Int(count))

        for _ in 0..<count {
            result.append(try readEntry(&self))
        }

        return result
    }

    @discardableResult public mutating func writeNFS3ResultStatus<O, F>(_ result: NFS3Result<O, F>) -> Int {
        self.writeInteger(result.status.rawValue, as: UInt32.self)
    }

    public mutating func readNFS3Status() throws -> NFS3Status {
        let rawValue = try self.readNFS3Integer(as: UInt32.self)
        if let status = NFS3Status(rawValue: rawValue) {
            return status
        } else {
            throw NFS3Error.invalidStatus(rawValue)
        }
    }

    public mutating func readRPCAuthFlavor() throws -> RPCAuthFlavor {
        let rawValue = try self.readNFS3Integer(as: UInt32.self)
        if let flavor = RPCAuthFlavor(rawValue: rawValue) {
            return flavor
        } else {
            throw RPCErrors.invalidAuthFlavor(rawValue)
        }
    }

    public mutating func readNFS3Result<O, F>(
        readOkay: (inout ByteBuffer) throws -> O,
        readFail: (inout ByteBuffer) throws -> F
    ) throws -> NFS3Result<O, F> {
        let status = try self.readNFS3Status()
        switch status {
        case .ok:
            return .okay(try readOkay(&self))
        default:
            return .fail(status, try readFail(&self))
        }
    }
}

public enum NFS3PartialWriteNextStep: Hashable & Sendable {
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
