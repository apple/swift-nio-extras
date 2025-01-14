//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019-2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOExtras
import NIOHTTP1
import NIOPosix

class SendSimpleRequestHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private let allDonePromise: EventLoopPromise<ByteBuffer>

    init(allDonePromise: EventLoopPromise<ByteBuffer>) {
        self.allDonePromise = allDonePromise
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case .body(let body) = self.unwrapInboundIn(data) {
            self.allDonePromise.succeed(body)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.allDonePromise.fail(error)
        context.close(promise: nil)
    }

    func channelActive(context: ChannelHandlerContext) {
        let headers = HTTPHeaders([
            ("host", "httpbin.org"),
            ("accept", "application/json"),
        ])
        context.write(
            self.wrapOutboundOut(
                .head(
                    .init(
                        version: .init(major: 1, minor: 1),
                        method: .GET,
                        uri: "/delay/0.2",
                        headers: headers
                    )
                )
            ),
            promise: nil
        )
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }
}

guard let outputFile = CommandLine.arguments.dropFirst().first else {
    print("Usage: \(CommandLine.arguments[0]) OUTPUT.pcap")
    exit(0)
}

let fileSink = try NIOWritePCAPHandler.SynchronizedFileSink.fileSinkWritingToFile(path: outputFile) { error in
    print("ERROR: \(error)")
    exit(1)
}

let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
defer {
    try! group.syncShutdownGracefully()
}
let allDonePromise = group.next().makePromise(of: ByteBuffer.self)
let connection = try ClientBootstrap(group: group.next())
    .channelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
            let sync = channel.pipeline.syncOperations
            try sync.addHandler(NIOWritePCAPHandler(mode: .client, fileSink: fileSink.write))
            try sync.addHTTPClientHandlers()
            try sync.addHandlers(SendSimpleRequestHandler(allDonePromise: allDonePromise))
        }
    }
    .connect(host: "httpbin.org", port: 80)
    .wait()
let bytesReceived = try allDonePromise.futureResult.wait()
print("# Success!", String(decoding: bytesReceived.readableBytesView, as: Unicode.UTF8.self), separator: "\n")
try connection.close().wait()
try fileSink.syncClose()
print("# Your pcap file should have been written to '\(outputFile)'")
print("#")
print("# You can view \(outputFile) with")
print("# - Wireshark")
print("# - tcpdump -r '\(outputFile)'")
