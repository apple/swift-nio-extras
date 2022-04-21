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

// MARK: - Read
public struct NFS3CallRead: Equatable {
    public init(fileHandle: NFS3FileHandle, offset: NFS3Offset, count: NFS3Count) {
        self.fileHandle = fileHandle
        self.offset = offset
        self.count = count
    }

    public var fileHandle: NFS3FileHandle
    public var offset: NFS3Offset
    public var count: NFS3Count
}

public struct NFS3ReplyRead: Equatable {
    public init(result: NFS3Result<NFS3ReplyRead.Okay, NFS3ReplyRead.Fail>) {
        self.result = result
    }

    public struct Okay: Equatable {
        public init(attributes: NFS3FileAttr? = nil, count: NFS3Count, eof: NFS3Bool, data: ByteBuffer) {
            self.attributes = attributes
            self.count = count
            self.eof = eof
            self.data = data
        }

        public var attributes: NFS3FileAttr?
        public var count: NFS3Count
        public var eof: NFS3Bool
        public var data: ByteBuffer
    }

    public struct Fail: Equatable {
        public init(attributes: NFS3FileAttr? = nil) {
            self.attributes = attributes
        }

        public var attributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFSCallRead() throws -> NFS3CallRead {
        let fileHandle = try self.readNFSFileHandle()
        guard let values = self.readMultipleIntegers(as: (NFS3Offset, NFS3Count).self) else {
            throw NFS3Error.illegalRPCTooShort
        }

        return NFS3CallRead(fileHandle: fileHandle, offset: values.0, count: values.1)
    }

    public mutating func writeNFSCallRead(_ call: NFS3CallRead) {
        self.writeNFSFileHandle(call.fileHandle)
        self.writeMultipleIntegers(call.offset, call.count, endianness: .big)
    }

    public mutating func readNFSReplyRead() throws -> NFS3ReplyRead {
        return NFS3ReplyRead(
            result: try self.readNFSResult(
                readOkay: { buffer in
                    let attrs = try buffer.readNFSOptional { buffer in
                        try buffer.readNFSFileAttr()
                    }
                    guard let values = buffer.readMultipleIntegers(as: (UInt32, UInt32).self) else {
                        throw NFS3Error.illegalRPCTooShort
                    }
                    let bytes = try buffer.readNFSBlob()
                    return NFS3ReplyRead.Okay(attributes: attrs,
                                             count: values.0,
                                             eof: values.1 == 0 ? false : true,
                                             data: bytes)
                },
                readFail: { buffer in
                    let attrs = try buffer.readNFSOptional { buffer in
                        try buffer.readNFSFileAttr()
                    }
                    return NFS3ReplyRead.Fail(attributes: attrs)
                })
        )
    }

    public mutating func writeNFSReplyReadPartially(_ read: NFS3ReplyRead) -> NFS3PartialWriteNextStep {
        switch read.result {
        case .okay(let result):
            self.writeInteger(NFS3Status.ok.rawValue, endianness: .big)
            self.writeNFSOptional(result.attributes, writer: { $0.writeNFSFileAttr($1) })
            self.writeMultipleIntegers(
                result.count,
                result.eof ? UInt32(1) : 0,
                UInt32(result.data.readableBytes)
            )
            return .writeBlob(result.data, numberOfFillBytes: nfsStringFillBytes(result.data.readableBytes))
        case .fail(let status, let fail):
            precondition(status != .ok)
            self.writeInteger(status.rawValue, endianness: .big)
            self.writeNFSOptional(fail.attributes, writer: { $0.writeNFSFileAttr($1) })
            return .doNothing
        }
    }

    public mutating func writeNFSReplyRead(_ read: NFS3ReplyRead) {
        switch self.writeNFSReplyReadPartially(read) {
        case .doNothing:
            ()
        case .writeBlob(let blob, numberOfFillBytes: let fillBytes):
            self.writeImmutableBuffer(blob)
            self.writeRepeatingByte(0x41, count: fillBytes)
        }
    }
}
