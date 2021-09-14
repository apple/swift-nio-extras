//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch

import NIOCore
import NIOPosix
import NIOHTTP1
import NIOExtras

private final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let req = self.unwrapInboundIn(data)
        switch req {
        case .head(let head):
            guard head.version == HTTPVersion(major: 1, minor: 1) else {
                context.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: head.version, status: .badRequest))), promise: nil)
                context.writeAndFlush(self.wrapOutboundOut(.end(nil))).whenComplete { (_: Result<(), Error>) in
                    context.close(promise: nil)
                }
                return
            }
        case .body:
            () // ignore
        case .end:
            var buffer = context.channel.allocator.buffer(capacity: 128)
            buffer.writeStaticString("received request; waiting 30s then finishing up request\n")
            buffer.writeStaticString("press Ctrl+C in the server's terminal or run the following command to initiate server shutdown\n")
            buffer.writeString("    kill -INT \(getpid())\n")
            context.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: HTTPVersion(major: 1, minor: 1),
                                                                  status: .ok))), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            buffer.clear()
            buffer.writeStaticString("done with the request now\n")
            _ = context.eventLoop.scheduleTask(in: .seconds(30)) { [buffer] in
                context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)

            }
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print(error)
    }
}

let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
let quiesce = ServerQuiescingHelper(group: group)

let signalQueue = DispatchQueue(label: "io.swift-nio.NIOExtrasDemo.SignalHandlingQueue")
let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
let fullyShutdownPromise: EventLoopPromise<Void> = group.next().makePromise()
signalSource.setEventHandler {
    signalSource.cancel()
    print("\nreceived signal, initiating shutdown which should complete after the last request finished.")

    quiesce.initiateShutdown(promise: fullyShutdownPromise)
}
signal(SIGINT, SIG_IGN)
signalSource.resume()

do {

    let serverChannel = try ServerBootstrap(group: group)
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .serverChannelInitializer { channel in
            channel.pipeline.addHandler(quiesce.makeServerChannelHandler(channel: channel))
        }
        .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
        .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
        .childChannelInitializer { channel in
            channel.pipeline.configureHTTPServerPipeline(withPipeliningAssistance: true, withErrorHandling: true).flatMap {
                channel.pipeline.addHandler(HTTPHandler())
            }
        }
        .bind(host: "localhost", port: 0)
        .wait()
    print("HTTP server up and running on \(serverChannel.localAddress!)")
    print("to connect to this server, run")
    print("    curl http://localhost:\(serverChannel.localAddress!.port!)")
} catch {
    try group.syncShutdownGracefully()
    throw error
}
try fullyShutdownPromise.futureResult.wait()
try group.syncShutdownGracefully()
