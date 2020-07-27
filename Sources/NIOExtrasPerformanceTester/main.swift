//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import NIOExtras
import NIOHTTP1
import Foundation

// MARK:  Setup
var warning: String = ""
assert({
    print("======================================================")
    print("= YOU ARE RUNNING NIOPerformanceTester IN DEBUG MODE =")
    print("======================================================")
    warning = " <<< DEBUG MODE >>>"
    return true
    }())

let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
defer {
    try! group.syncShutdownGracefully()
}

let serverChannel = try ServerBootstrap(group: group)
    .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
    .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline(withPipeliningAssistance: true).flatMap {
            channel.pipeline.addHandler(SimpleHTTPServer())
        }
    }.bind(host: "127.0.0.1", port: 0).wait()

defer {
    try! serverChannel.close().wait()
}

// MARK: HTTP1 Performance
var head = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "/perf-test-1")
head.headers.add(name: "Host", value: "localhost")


// Not going to be super stable timings due to use of threads but feels a bit real worldy.
private func testHttp1Performance(numberOfRepeats: Int,
                                  numberOfClients: Int,
                                  requestsPerClient: Int,
                                  extraInitialiser: @escaping (Channel) -> EventLoopFuture<Void>) -> Int {
    var reqs: [Int] = []
    reqs.reserveCapacity(numberOfRepeats)
    for _ in 0..<numberOfRepeats {
        var requestHandlers: [RepeatedRequests] = []
        requestHandlers.reserveCapacity(numberOfClients)
        var clientChannels: [Channel] = []
        clientChannels.reserveCapacity(numberOfClients)
        for _ in 0 ..< numberOfClients {
            let clientChannel = try! ClientBootstrap(group: group)
                .channelInitializer { channel in
                    channel.pipeline.addHTTPClientHandlers().flatMap {
                        let repeatedRequestsHandler = RepeatedRequests(numberOfRequests: requestsPerClient,
                                                                   eventLoop: channel.eventLoop)
                        requestHandlers.append(repeatedRequestsHandler)
                        return channel.pipeline.addHandler(repeatedRequestsHandler)
                    }.flatMap {
                        extraInitialiser(channel)
                    }
                }
                .connect(to: serverChannel.localAddress!)
                .wait()
            clientChannels.append(clientChannel)
        }

        var writeFutures: [EventLoopFuture<Void>] = []
        for clientChannel in clientChannels {
            clientChannel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
            writeFutures.append(clientChannel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil))))
        }
        let allWrites = EventLoopFuture<Void>.andAllComplete(writeFutures, on: writeFutures.first!.eventLoop)
        try! allWrites.wait()

        let streamCompletedFutures = requestHandlers.map { rh in rh.completedFuture }
        let requestsServed = EventLoopFuture<Int>.reduce(0, streamCompletedFutures, on: streamCompletedFutures.first!.eventLoop, +)
        reqs.append(try! requestsServed.wait())
    }
    return reqs.reduce(0, +) / numberOfRepeats
}

// MARK:  Tests
measureAndPrint(desc: "http1_threaded_50reqs_500conns") {
    testHttp1Performance(numberOfRepeats: 50,
                         numberOfClients: System.coreCount,
                         requestsPerClient: 500,
                         extraInitialiser: { channel in return channel.eventLoop.makeSucceededFuture(()) })
}

measureAndPrint(desc: "http1_threaded_50reqs_500conns_rolling_pcap") {
    func addRollingPCap(channel: Channel) -> EventLoopFuture<Void> {
        let pcapRingBuffer = NIOPCAPRingBuffer(maximumFragments: 25,
                                               maximumBytes: 1_000_000)
        let pcapHandler = NIOWritePCAPHandler(mode: .client,
                                              fileSink: pcapRingBuffer.addFragment)
        return channel.pipeline.addHandler(pcapHandler, position: .first)
    }

    return testHttp1Performance(numberOfRepeats: 50,
                                numberOfClients: System.coreCount,
                                requestsPerClient: 500,
                                extraInitialiser: { channel in return addRollingPCap(channel: channel) })
}

try! measureAndPrint(desc: "http1_threaded_50reqs_500conns_rolling_pcap") {
    let outputFile = NSTemporaryDirectory() + "/" + ProcessInfo().globallyUniqueString
    let fileSink = try NIOWritePCAPHandler.SynchronizedFileSink.fileSinkWritingToFile(path: outputFile) { error in
        print("ERROR: \(error)")
        exit(1)
    }
    defer {
        try! fileSink.syncClose()
    }

    func addPCap(channel: Channel) -> EventLoopFuture<Void> {
        let pcapHandler = NIOWritePCAPHandler(mode: .client,
                                              fileSink: fileSink.write)
        return channel.pipeline.addHandler(pcapHandler, position: .first)
    }

    return testHttp1Performance(numberOfRepeats: 50,
                                numberOfClients: System.coreCount,
                                requestsPerClient: 500,
                                extraInitialiser: { channel in return addPCap(channel: channel) })
}
