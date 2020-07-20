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

import NIO
import NIOExtras
import NIOHTTP1



class TriggerPCAPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case .head(let header) = self.unwrapInboundIn(data) {
            if header.status == .preconditionFailed {
                // For the sake of a repeatable demo, let's assume that seeing a preconditionFailed
                // status is the sign that the issue you're looking to diagnose has happened.
                // Obviously in real usage there will be a hypothesis you're trying to test
                // which should give the trigger condition.
                context.triggerUserOutboundEvent(NIOPCAPRingCaptureHandler.RecordPreviousPackets(),
                                                 promise: nil)
            }
        }
        context.fireChannelRead(data)
    }
}

class SendSimpleSequenceRequestHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart
    
    private let allDonePromise: EventLoopPromise<Void>

    private var nextReqeustNumber = 0
    private var requestsToMake: [HTTPResponseStatus] = [ .ok, .created, .accepted, .nonAuthoritativeInformation,
                                                         .noContent, .resetContent, .preconditionFailed,
                                                         .partialContent, .multiStatus, .alreadyReported ]

    init(allDonePromise: EventLoopPromise<Void>) {
        self.allDonePromise = allDonePromise
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case .end = self.unwrapInboundIn(data) {
            makeNextReqeustOrComplete(context: context)
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.allDonePromise.fail(error)
        context.close(promise: nil)
    }
    
    func channelActive(context: ChannelHandlerContext) {
        makeNextReqeustOrComplete(context: context)
    }

    private func makeNextReqeustOrComplete(context: ChannelHandlerContext) {
        if self.nextReqeustNumber < self.requestsToMake.count {
            let headers = HTTPHeaders([("host", "httpbin.org"),
                                       ("accept", "application/json")])
            let currentStatus = self.requestsToMake[self.nextReqeustNumber].code
            self.nextReqeustNumber += 1
            context.write(self.wrapOutboundOut(.head(.init(version: .init(major: 1, minor: 1),
                                                           method: .GET,
                                                           uri: "/status/\(currentStatus)",
                                                           headers: headers))), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        } else {
            self.allDonePromise.succeed(())
        }
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
let allDonePromise = group.next().makePromise(of: Void.self)
let maximumFragments: UInt = 4
let connection = try ClientBootstrap(group: group.next())
    .channelInitializer { channel in
        return channel.pipeline.addHandler(NIOPCAPRingCaptureHandler(maximumFragments: maximumFragments,
                                                                     maximumBytes: 1_000_000,
                                                                     sink: fileSink.write)).flatMap {
            channel.pipeline.addHTTPClientHandlers()
        }.flatMap {
            channel.pipeline.addHandler(TriggerPCAPHandler())
        }.flatMap {
            channel.pipeline.addHandler(SendSimpleSequenceRequestHandler(allDonePromise: allDonePromise))
        }
    }
    .connect(host: "httpbin.org", port: 80)
    .wait()
try allDonePromise.futureResult.wait()
print("# Success!")
try connection.close().wait()
try fileSink.syncClose()
print("# Your pcap file should have been written to '\(outputFile)'")
print(" This should contain the \(maximumFragments) fragments leading up to PRECONDITION FAILED status")
print("#")
print("# You can view \(outputFile) with")
print("# - Wireshark")
print("# - tcpdump -r '\(outputFile)'")
