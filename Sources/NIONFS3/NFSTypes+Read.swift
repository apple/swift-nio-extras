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

// MARK: - Read
public struct NFS3CallRead: Hashable & Sendable {
    public init(fileHandle: NFS3FileHandle, offset: NFS3Offset, count: NFS3Count) {
        self.fileHandle = fileHandle
        self.offset = offset
        self.count = count
    }

    public var fileHandle: NFS3FileHandle
    public var offset: NFS3Offset
    public var count: NFS3Count
}

public struct NFS3ReplyRead: Hashable & Sendable {
    public init(result: NFS3Result<NFS3ReplyRead.Okay, NFS3ReplyRead.Fail>) {
        self.result = result
    }

    public struct Okay: Hashable & Sendable {
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

    public struct Fail: Hashable & Sendable {
        public init(attributes: NFS3FileAttr? = nil) {
            self.attributes = attributes
        }

        public var attributes: NFS3FileAttr?
    }

    public var result: NFS3Result<Okay, Fail>
}

extension ByteBuffer {
    public mutating func readNFS3CallRead() throws -> NFS3CallRead {
        let fileHandle = try self.readNFS3FileHandle()
        guard let values = self.readMultipleIntegers(as: (NFS3Offset.RawValue, NFS3Count.RawValue).self) else {
            throw NFS3Error.illegalRPCTooShort
        }

        return NFS3CallRead(
            fileHandle: fileHandle,
            offset: .init(rawValue: values.0),
            count: .init(rawValue: values.1)
        )
    }

    @discardableResult public mutating func writeNFS3CallRead(_ call: NFS3CallRead) -> Int {
        self.writeNFS3FileHandle(call.fileHandle)
            + self.writeMultipleIntegers(call.offset.rawValue, call.count.rawValue)
    }

    public mutating func readNFS3ReplyRead() throws -> NFS3ReplyRead {
        NFS3ReplyRead(
            result: try self.readNFS3Result(
                readOkay: { buffer in
                    let attrs = try buffer.readNFS3Optional { buffer in
                        try buffer.readNFS3FileAttr()
                    }
                    guard let values = buffer.readMultipleIntegers(as: (UInt32, UInt32).self) else {
                        throw NFS3Error.illegalRPCTooShort
                    }
                    let bytes = try buffer.readNFS3Blob()
                    return NFS3ReplyRead.Okay(
                        attributes: attrs,
                        count: NFS3Count(rawValue: values.0),
                        eof: values.1 == 0 ? false : true,
                        data: bytes
                    )
                },
                readFail: { buffer in
                    let attrs = try buffer.readNFS3Optional { buffer in
                        try buffer.readNFS3FileAttr()
                    }
                    return NFS3ReplyRead.Fail(attributes: attrs)
                }
            )
        )
    }

    public mutating func writeNFS3ReplyReadPartially(_ read: NFS3ReplyRead) -> NFS3PartialWriteNextStep {
        switch read.result {
        case .okay(let result):
            self.writeInteger(NFS3Status.ok.rawValue)
            self.writeNFS3Optional(result.attributes, writer: { $0.writeNFS3FileAttr($1) })
            self.writeMultipleIntegers(
                result.count.rawValue,
                result.eof ? UInt32(1) : 0,
                UInt32(result.data.readableBytes)
            )
            return .writeBlob(result.data, numberOfFillBytes: nfsStringFillBytes(result.data.readableBytes))
        case .fail(let status, let fail):
            precondition(status != .ok)
            self.writeInteger(status.rawValue)
            self.writeNFS3Optional(fail.attributes, writer: { $0.writeNFS3FileAttr($1) })
            return .doNothing
        }
    }

    @discardableResult public mutating func writeNFS3ReplyRead(_ read: NFS3ReplyRead) -> Int {
        switch self.writeNFS3ReplyReadPartially(read) {
        case .doNothing:
            return 0
        case .writeBlob(let blob, numberOfFillBytes: let fillBytes):
            return self.writeImmutableBuffer(blob)
                + self.writeRepeatingByte(0x41, count: fillBytes)
        }
    }
}
