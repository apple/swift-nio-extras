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

import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix

// MARK: Handlers
final class SimpleHTTPServer: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var files: [String] = []
    private var seenEnd = false
    private var sentEnd = false
    private var isOpen = true

    private let cachedHead: HTTPResponseHead
    private let cachedBody: [UInt8]
    private let bodyLength = 1024
    private let numberOfAdditionalHeaders = 10

    init() {
        var head = HTTPResponseHead(version: HTTPVersion(major: 1, minor: 1), status: .ok)
        head.headers.add(name: "Content-Length", value: "\(self.bodyLength)")
        for i in 0..<self.numberOfAdditionalHeaders {
            head.headers.add(name: "X-Random-Extra-Header", value: "\(i)")
        }
        self.cachedHead = head

        var body: [UInt8] = []
        body.reserveCapacity(self.bodyLength)
        for i in 0..<self.bodyLength {
            body.append(UInt8(i % Int(UInt8.max)))
        }
        self.cachedBody = body
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case .head(let req) = self.unwrapInboundIn(data) {
            switch req.uri {
            case "/perf-test-1":
                var buffer = context.channel.allocator.buffer(capacity: self.cachedBody.count)
                buffer.writeBytes(self.cachedBody)
                context.write(self.wrapOutboundOut(.head(self.cachedHead)), promise: nil)
                context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
                return
            case "/perf-test-2":
                var req = HTTPResponseHead(version: HTTPVersion(major: 1, minor: 1), status: .ok)
                for i in 1...8 {
                    req.headers.add(name: "X-ResponseHeader-\(i)", value: "foo")
                }
                req.headers.add(name: "content-length", value: "0")
                context.write(self.wrapOutboundOut(.head(req)), promise: nil)
                context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
                return
            default:
                fatalError("unknown uri \(req.uri)")
            }
        }
    }
}

final class RepeatedRequests: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private let numberOfRequests: Int
    private var remainingNumberOfRequests: Int
    private var doneRequests = 0
    private let isDonePromise: EventLoopPromise<Int>
    private let head: HTTPRequestHead

    init(numberOfRequests: Int, eventLoop: EventLoop, head: HTTPRequestHead) {
        self.remainingNumberOfRequests = numberOfRequests
        self.numberOfRequests = numberOfRequests
        self.isDonePromise = eventLoop.makePromise()
        self.head = head
    }

    func wait() throws -> Int {
        let reqs = try self.isDonePromise.futureResult.wait()
        precondition(reqs == self.numberOfRequests)
        return reqs
    }

    var completedFuture: EventLoopFuture<Int> { self.isDonePromise.futureResult }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.channel.close(promise: nil)
        self.isDonePromise.fail(error)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        if case .end(nil) = reqPart {
            if self.remainingNumberOfRequests <= 0 {
                context.channel.close().assumeIsolated().map { self.doneRequests }.nonisolated().cascade(
                    to: self.isDonePromise
                )
            } else {
                self.doneRequests += 1
                self.remainingNumberOfRequests -= 1

                context.write(self.wrapOutboundOut(.head(self.head)), promise: nil)
                context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }
        }
    }
}

// MARK: ThreadedPerfTest
class HTTP1ThreadedPerformanceTest: Benchmark {
    let numberOfRepeats: Int
    let numberOfClients: Int
    let requestsPerClient: Int
    let extraInitialiser: @Sendable (Channel) -> EventLoopFuture<Void>

    let head: HTTPRequestHead

    var group: MultiThreadedEventLoopGroup!
    var serverChannel: Channel!

    init(
        numberOfRepeats: Int,
        numberOfClients: Int,
        requestsPerClient: Int,
        extraInitialiser: @escaping @Sendable (Channel) -> EventLoopFuture<Void>
    ) {
        self.numberOfRepeats = numberOfRepeats
        self.numberOfClients = numberOfClients
        self.requestsPerClient = requestsPerClient
        self.extraInitialiser = extraInitialiser

        var head = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: "/perf-test-1")
        head.headers.add(name: "Host", value: "localhost")
        self.head = head
    }

    func setUp() throws {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.serverChannel = try ServerBootstrap(group: self.group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let sync = channel.pipeline.syncOperations
                    try sync.configureHTTPServerPipeline(withPipeliningAssistance: true)
                    try sync.addHandler(SimpleHTTPServer())
                }
            }.bind(host: "127.0.0.1", port: 0).wait()
    }

    func tearDown() {
        try! self.serverChannel.close().wait()
        try! self.group.syncShutdownGracefully()
    }

    func run() throws -> Int {
        var reqs: [Int] = []
        reqs.reserveCapacity(self.numberOfRepeats)
        for _ in 0..<self.numberOfRepeats {
            let requestsCompletedFutures = NIOLockedValueBox<[EventLoopFuture<Int>]>([])
            requestsCompletedFutures.withLockedValue({ $0.reserveCapacity(self.numberOfClients) })

            var clientChannels: [Channel] = []
            clientChannels.reserveCapacity(self.numberOfClients)
            for _ in 0..<self.numberOfClients {
                let clientChannel = try! ClientBootstrap(group: self.group)
                    .channelInitializer { [head, requestsPerClient, extraInitialiser] channel in
                        channel.eventLoop.makeCompletedFuture {
                            let sync = channel.pipeline.syncOperations
                            try sync.addHTTPClientHandlers()

                            let repeatedRequestsHandler = RepeatedRequests(
                                numberOfRequests: requestsPerClient,
                                eventLoop: channel.eventLoop,
                                head: head
                            )

                            requestsCompletedFutures.withLockedValue {
                                $0.append(repeatedRequestsHandler.completedFuture)
                            }

                            try sync.addHandler(repeatedRequestsHandler)
                        }.flatMap {
                            extraInitialiser(channel)
                        }
                    }
                    .connect(to: self.serverChannel.localAddress!)
                    .wait()
                clientChannels.append(clientChannel)
            }

            var writeFutures: [EventLoopFuture<Void>] = []
            for clientChannel in clientChannels {
                clientChannel.write(HTTPClientRequestPart.head(self.head), promise: nil)
                writeFutures.append(clientChannel.writeAndFlush(HTTPClientRequestPart.end(nil)))
            }
            let allWrites = EventLoopFuture<Void>.andAllComplete(writeFutures, on: writeFutures.first!.eventLoop)
            try! allWrites.wait()

            let futures = requestsCompletedFutures.withLockedValue { $0 }
            let requestsServed = EventLoopFuture<Int>.reduce(
                0,
                futures,
                on: futures.first!.eventLoop
            ) { $0 + $1 }
            reqs.append(try! requestsServed.wait())
        }
        return reqs.reduce(0, +) / self.numberOfRepeats
    }
}
