//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the SwiftNIO project authors
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

/// Trigger recording pcap data when a "precondition failed" is seen.
class TriggerPCAPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private let pcapRingBuffer: NIOPCAPRingBuffer
    private let sink: (ByteBuffer) -> Void

    init(pcapRingBuffer: NIOPCAPRingBuffer, sink: @escaping (ByteBuffer) -> Void) {
        self.pcapRingBuffer = pcapRingBuffer
        self.sink = sink
    }

    private func capturedFragmentSink(captured: CircularBuffer<ByteBuffer>) {
        for buffer in captured {
            self.sink(buffer)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case .head(let header) = self.unwrapInboundIn(data) {
            if header.status == .preconditionFailed {
                // For the sake of a repeatable demo, let's assume that seeing a preconditionFailed
                // status is the sign that the issue you're looking to diagnose has happened.
                // Obviously in real usage there will be a hypothesis you're trying to test
                // which should give the trigger condition.
                let capturedFragments = self.pcapRingBuffer.emitPCAP()
                self.capturedFragmentSink(captured: capturedFragments)
            }
        }
        context.fireChannelRead(data)
    }
}

/// Makes a series of http requests which get known responses.
class SendSimpleSequenceRequestHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private let allDonePromise: EventLoopPromise<Void>

    private var nextRequestNumber = 0
    private var requestsToMake: [HTTPResponseStatus] = [
        .ok, .created, .accepted, .nonAuthoritativeInformation,
        .noContent, .resetContent, .preconditionFailed,
        .partialContent, .multiStatus, .alreadyReported,
    ]

    init(allDonePromise: EventLoopPromise<Void>) {
        self.allDonePromise = allDonePromise
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case .end = self.unwrapInboundIn(data) {
            self.makeNextRequestOrComplete(context: context)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.allDonePromise.fail(error)
        context.close(promise: nil)
    }

    func channelActive(context: ChannelHandlerContext) {
        self.makeNextRequestOrComplete(context: context)
    }

    private func makeNextRequestOrComplete(context: ChannelHandlerContext) {
        if self.nextRequestNumber < self.requestsToMake.count {
            let headers = HTTPHeaders([
                ("host", "httpbin.org"),
                ("accept", "application/json"),
            ])
            let currentStatus = self.requestsToMake[self.nextRequestNumber].code
            self.nextRequestNumber += 1
            context.write(
                self.wrapOutboundOut(
                    .head(
                        .init(
                            version: .init(major: 1, minor: 1),
                            method: .GET,
                            uri: "/status/\(currentStatus)",
                            headers: headers
                        )
                    )
                ),
                promise: nil
            )
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
let maximumFragments = 4
let connection = try ClientBootstrap(group: group.next())
    .channelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
            let pcapRingBuffer = NIOPCAPRingBuffer(
                maximumFragments: maximumFragments,
                maximumBytes: 1_000_000
            )
            try channel.pipeline.syncOperations.addHandler(
                NIOWritePCAPHandler(
                    mode: .client,
                    fileSink: pcapRingBuffer.addFragment
                )
            )
            try channel.pipeline.syncOperations.addHTTPClientHandlers()
            try channel.pipeline.syncOperations.addHandlers([
                TriggerPCAPHandler(pcapRingBuffer: pcapRingBuffer, sink: fileSink.write),
                SendSimpleSequenceRequestHandler(allDonePromise: allDonePromise),
            ])
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
