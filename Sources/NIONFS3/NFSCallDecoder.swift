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

public struct NFS3CallDecoder: NIOSingleStepByteToMessageDecoder, Sendable {
    public typealias InboundOut = RPCNFS3Call

    public init() {}

    public mutating func decode(buffer: inout ByteBuffer) throws -> RPCNFS3Call? {
        guard let message = try buffer.readRPCMessage() else {
            return nil
        }

        guard case (.call(let call), var body) = message else {
            throw NFS3Error.wrongMessageType(message.0)
        }

        return try body.readNFS3Call(rpc: call)
    }

    public mutating func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> RPCNFS3Call? {
        try self.decode(buffer: &buffer)
    }
}
