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

// MARK: - FSInfo
public struct NFS3CallFSInfo: Hashable & Sendable {
    public init(fsroot: NFS3FileHandle) {
        self.fsroot = fsroot
    }

    public var fsroot: NFS3FileHandle
}

public struct NFS3ReplyFSInfo: Hashable & Sendable {
    public init(result: NFS3Result<NFS3ReplyFSInfo.Okay, NFS3ReplyFSInfo.Fail>) {
        self.result = result
    }

    public struct Properties: OptionSet & Hashable & Sendable {
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

    public struct Okay: Hashable & Sendable {
        public init(
            attributes: NFS3FileAttr?,
            rtmax: UInt32,
            rtpref: UInt32,
            rtmult: UInt32,
            wtmax: UInt32,
            wtpref: UInt32,
            wtmult: UInt32,
            dtpref: UInt32,
            maxFileSize: NFS3Size,
            timeDelta: NFS3Time,
            properties: NFS3ReplyFSInfo.Properties
        ) {
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

    public struct Fail: Hashable & Sendable {
        public init(attributes: NFS3FileAttr?) {
            self.attributes = attributes
        }

        public var attributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFS3CallFSInfo() throws -> NFS3CallFSInfo {
        let fileHandle = try self.readNFS3FileHandle()
        return NFS3CallFSInfo(fsroot: fileHandle)
    }

    @discardableResult public mutating func writeNFS3CallFSInfo(_ call: NFS3CallFSInfo) -> Int {
        self.writeNFS3FileHandle(call.fsroot)
    }

    private mutating func readNFS3CallFSInfoProperties() throws -> NFS3ReplyFSInfo.Properties {
        let rawValue = try self.readNFS3Integer(as: UInt32.self)
        return NFS3ReplyFSInfo.Properties(rawValue: rawValue)
    }

    @discardableResult public mutating func writeNFS3ReplyFSInfo(_ reply: NFS3ReplyFSInfo) -> Int {
        var bytesWritten = self.writeNFS3ResultStatus(reply.result)

        switch reply.result {
        case .okay(let reply):
            bytesWritten +=
                self.writeNFS3Optional(reply.attributes, writer: { $0.writeNFS3FileAttr($1) })
                + self.writeMultipleIntegers(
                    reply.rtmax,
                    reply.rtpref,
                    reply.rtmult,
                    reply.wtmax,
                    reply.wtpref,
                    reply.wtmult,
                    reply.dtpref,
                    reply.maxFileSize.rawValue
                )
                + self.writeNFS3Time(reply.timeDelta)
                + self.writeInteger(reply.properties.rawValue)
        case .fail(_, let fail):
            bytesWritten += self.writeNFS3Optional(fail.attributes, writer: { $0.writeNFS3FileAttr($1) })
        }
        return bytesWritten
    }

    private mutating func readNFS3ReplyFSInfoOkay() throws -> NFS3ReplyFSInfo.Okay {
        let fileAttr = try self.readNFS3Optional { try $0.readNFS3FileAttr() }
        guard let values = self.readMultipleIntegers(as: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32).self)
        else {
            throw NFS3Error.illegalRPCTooShort
        }
        let rtmax = values.0
        let rtpref = values.1
        let rtmult = values.2
        let wtmax = values.3
        let wtpref = values.4
        let wtmult = values.5
        let dtpref = values.6
        let maxFileSize = try self.readNFS3Size()
        let timeDelta = try self.readNFS3Time()
        let properties = try self.readNFS3CallFSInfoProperties()

        return .init(
            attributes: fileAttr,
            rtmax: rtmax,
            rtpref: rtpref,
            rtmult: rtmult,
            wtmax: wtmax,
            wtpref: wtpref,
            wtmult: wtmult,
            dtpref: dtpref,
            maxFileSize: maxFileSize,
            timeDelta: timeDelta,
            properties: properties
        )
    }

    public mutating func readNFS3ReplyFSInfo() throws -> NFS3ReplyFSInfo {
        NFS3ReplyFSInfo(
            result: try self.readNFS3Result(
                readOkay: { try $0.readNFS3ReplyFSInfoOkay() },
                readFail: { NFS3ReplyFSInfo.Fail(attributes: try $0.readNFS3FileAttr()) }
            )
        )
    }
}
