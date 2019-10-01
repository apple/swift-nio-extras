//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CNIOExtrasZlib
import NIOHTTP1
import NIO

public final class NIOHTTPRequestDecompressor: ChannelDuplexHandler, RemovableChannelHandler {
    public typealias InboundIn = HTTPClientRequestPart
    public typealias InboundOut = HTTPClientRequestPart
    public typealias OutboundIn = HTTPClientResponsePart
    public typealias OutboundOut = HTTPClientResponsePart

    
}
