//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2022-2023 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

public struct PCAPDecoder: NIOSingleStepByteToMessageDecoder {
    public typealias InboundOut = PCAPRecord

    private enum State {
        case header
        case record(PCAP2Header)
    }

    private var state = State.header

    public mutating func decode(buffer: inout ByteBuffer) throws -> PCAPRecord? {
        switch self.state {
        case .header:
            if let header = try buffer.readPCAP2Header() {
                self.state = .record(header)
            }
            return nil
        case .record(let header):
            return buffer.readPCAPRecord(endianness: header.endianness)
        }
    }

    public mutating func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> PCAPRecord? {
        return try self.decode(buffer: &buffer)
    }
}
