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

// MARK: - FSInfo
public struct NFS3CallFSInfo: Equatable {
    public init(fsroot: NFS3FileHandle) {
        self.fsroot = fsroot
    }

    public var fsroot: NFS3FileHandle
}

public struct NFS3ReplyFSInfo: Equatable {
    public init(result: NFS3Result<NFS3ReplyFSInfo.Okay, NFS3ReplyFSInfo.Fail>) {
        self.result = result
    }

    public struct Properties: OptionSet {
        public typealias RawValue = UInt32

        public var rawValue: RawValue

        public init(rawValue: RawValue) {
            self.rawValue = rawValue
        }

        public static let supportsHardlinks: Self = .init(rawValue: (1 << 0))
        public static let supportsSoftlinks: Self = .init(rawValue: (1 << 1))
        public static let isHomogenous: Self = .init(rawValue: (1 << 2))
        public static let canSetTime: Self = .init(rawValue: (1 << 3))
        public static let `default`: Self = [.supportsSoftlinks, .supportsHardlinks, .isHomogenous, .canSetTime]
    }

    public struct Okay: Equatable {
        public init(attributes: NFS3FileAttr?,
                    rtmax: UInt32, rtpref: UInt32, rtmult: UInt32,
                    wtmax: UInt32, wtpref: UInt32, wtmult: UInt32,
                    dtpref: UInt32,
                    maxFileSize: NFS3Size,
                    timeDelta: NFS3Time,
                    properties: NFS3ReplyFSInfo.Properties) {
            self.attributes = attributes
            self.rtmax = rtmax
            self.rtpref = rtpref
            self.rtmult = rtmult
            self.wtmax = wtmax
            self.wtpref = wtpref
            self.wtmult = wtmult
            self.dtpref = dtpref
            self.maxFileSize = maxFileSize
            self.timeDelta = timeDelta
            self.properties = properties
        }

        public var attributes: NFS3FileAttr?
        public var rtmax: UInt32
        public var rtpref: UInt32
        public var rtmult: UInt32
        public var wtmax: UInt32
        public var wtpref: UInt32
        public var wtmult: UInt32
        public var dtpref: UInt32
        public var maxFileSize: NFS3Size
        public var timeDelta: NFS3Time
        public var properties: Properties = .default
    }

    public struct Fail: Equatable {
        public init(attributes: NFS3FileAttr?) {
            self.attributes = attributes
        }

        public var attributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFSCallFSInfo() throws -> NFS3CallFSInfo {
        let fileHandle = try self.readNFSFileHandle()
        return NFS3CallFSInfo(fsroot: fileHandle)
    }

    public mutating func writeNFSCallFSInfo(_ call: NFS3CallFSInfo) {
        self.writeNFSFileHandle(call.fsroot)
    }

    private mutating func readNFSCallFSInfoProperties() throws -> NFS3ReplyFSInfo.Properties {
        let rawValue = try self.readNFSInteger(as: UInt32.self)
        return NFS3ReplyFSInfo.Properties(rawValue: rawValue)
    }

    public mutating func writeNFSReplyFSInfo(_ reply: NFS3ReplyFSInfo) {
        self.writeNFSResultStatus(reply.result)

        switch reply.result {
        case .okay(let reply):
            self.writeNFSOptional(reply.attributes, writer: { $0.writeNFSFileAttr($1) })
            self.writeMultipleIntegers(
                reply.rtmax,
                reply.rtpref,
                reply.rtmult,
                reply.wtmax,
                reply.wtpref,
                reply.wtmult,
                reply.dtpref,
                reply.maxFileSize,
                endianness: .big)
            self.writeNFSTime(reply.timeDelta)
            self.writeInteger(reply.properties.rawValue, endianness: .big)
        case .fail(_, let fail):
            self.writeNFSOptional(fail.attributes, writer: { $0.writeNFSFileAttr($1) })
        }
    }

    private mutating func readNFSReplyFSInfoOkay() throws -> NFS3ReplyFSInfo.Okay {
        let fileAttr = try self.readNFSOptional { try $0.readNFSFileAttr() }
        guard let values = self.readMultipleIntegers(endianness: .big,
                                                      as: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32).self) else {
            throw NFS3Error.illegalRPCTooShort
        }
        let rtmax = values.0
        let rtpref = values.1
        let rtmult = values.2
        let wtmax = values.3
        let wtpref = values.4
        let wtmult = values.5
        let dtpref = values.6
        let maxFileSize = try self.readNFSSize()
        let timeDelta = try self.readNFSTime()
        let properties = try self.readNFSCallFSInfoProperties()

        return .init(attributes: fileAttr,
                     rtmax: rtmax, rtpref: rtpref, rtmult: rtmult,
                     wtmax: wtmax, wtpref: wtpref, wtmult: wtmult,
                     dtpref: dtpref,
                     maxFileSize: maxFileSize, timeDelta: timeDelta, properties: properties)
    }

    public mutating func readNFSReplyFSInfo() throws -> NFS3ReplyFSInfo {
        return NFS3ReplyFSInfo(result: try self.readNFSResult(
            readOkay: { try $0.readNFSReplyFSInfoOkay() },
            readFail: { NFS3ReplyFSInfo.Fail(attributes: try $0.readNFSFileAttr()) }
        ))
    }
}
