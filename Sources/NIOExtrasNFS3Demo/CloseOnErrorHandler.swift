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

import Logging
import NIOCore

final class CloseOnErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Never

    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.logger.warning("encountered error, closing NFS connection", metadata: ["error": "\(error)"])
        context.close(promise: nil)
    }
}
