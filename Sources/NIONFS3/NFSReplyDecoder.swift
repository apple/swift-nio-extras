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

public struct NFS3ReplyDecoder: WriteObservingByteToMessageDecoder {
    public typealias OutboundIn = RPCNFS3Call
    public typealias InboundOut = RPCNFS3Reply

    private var procedures: [UInt32: RPCNFS3ProcedureID]
    private let allowDuplicateReplies: Bool

    /// Initialize the `NFS3ReplyDecoder`.
    ///
    /// - Parameters:
    ///   - prepopulatedProcecedures: For testing and other more obscure purposes it might be useful to pre-seed the
    ///                               decoder with some RPC numbers and their respective type.
    ///   - allowDuplicateReplies: Whether to fail when receiving more than one response for a given call.
    public init(
        prepopulatedProcecedures: [UInt32: RPCNFS3ProcedureID]? = nil,
        allowDuplicateReplies: Bool = false
    ) {
        self.procedures = prepopulatedProcecedures ?? [:]
        self.allowDuplicateReplies = allowDuplicateReplies
    }

    public mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard let message = try buffer.readRPCMessage() else {
            return .needMoreData
        }

        guard case (.reply(let reply), var body) = message else {
            throw NFS3Error.wrongMessageType(message.0)
        }

        let progAndProc: RPCNFS3ProcedureID
        if allowDuplicateReplies {
            // for tests mainly
            guard let p = self.procedures[reply.xid] else {
                throw NFS3Error.unknownXID(reply.xid)
            }
            progAndProc = p
        } else {
            guard let p = self.procedures.removeValue(forKey: reply.xid) else {
                throw NFS3Error.unknownXID(reply.xid)
            }
            progAndProc = p
        }

        let nfsReply = try body.readNFS3Reply(programAndProcedure: progAndProc, rpcReply: reply)
        context.fireChannelRead(self.wrapInboundOut(nfsReply))
        return .continue
    }

    public mutating func write(data: RPCNFS3Call) {
        self.procedures[data.rpcCall.xid] = data.rpcCall.programAndProcedure
    }
}

@available(*, unavailable)
extension NFS3ReplyDecoder: Sendable {}
