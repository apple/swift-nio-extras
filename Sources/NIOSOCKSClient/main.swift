//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import NIOSSL
import NIOSOCKS

let sslContext = try! NIOSSLContext(configuration: .clientDefault)

let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
let bootstrap = ClientBootstrap(group: elg)
    .channelInitializer { channel in
        channel.pipeline.addHandlers([
            SocksClientHandler(supportedAuthenticationMethods: [.noneRequired])
        ])
}
let channel = try bootstrap.connect(host: "127.0.0.1", port: 1080).wait()
try channel.closeFuture.wait()
print("Connection closed")
