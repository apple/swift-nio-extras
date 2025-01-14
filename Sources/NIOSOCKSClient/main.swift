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

import NIOCore
import NIOPosix
import NIOSOCKS

class EchoHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.writeAndFlush(data, promise: nil)
    }

}

let targetIPAddress = "127.0.0.1"
let targetPort = 12345
let targetAddress = SOCKSAddress.address(try SocketAddress(ipAddress: targetIPAddress, port: targetPort))

let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
let bootstrap = ClientBootstrap(group: elg)
    .channelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
            let sync = channel.pipeline.syncOperations
            try sync.addHandler(SOCKSClientHandler(targetAddress: targetAddress))
            try sync.addHandler(EchoHandler())
        }
    }
let channel = try bootstrap.connect(host: "127.0.0.1", port: 1080).wait()

while let string = readLine(strippingNewline: true) {
    let buffer = ByteBuffer(string: string)
    channel.writeAndFlush(buffer, promise: nil)
}
