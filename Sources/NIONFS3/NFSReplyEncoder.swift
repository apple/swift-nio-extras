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

public struct NFS3ReplyEncoder: MessageToByteEncoder, Sendable {
    public typealias OutboundIn = RPCNFS3Reply

    public init() {}

    public func encode(data: RPCNFS3Reply, out: inout ByteBuffer) throws {
        out.writeRPCNFS3Reply(data)
    }
}
