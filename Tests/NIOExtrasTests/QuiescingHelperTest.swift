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

import NIOCore
import NIOEmbedded
import NIOPosix
import NIOTestUtils
import XCTest

@testable import NIOExtras

private final class WaitForQuiesceUserEvent: ChannelInboundHandler {
    typealias InboundIn = Never
    private let promise: EventLoopPromise<Void>

    init(promise: EventLoopPromise<Void>) {
        self.promise = promise
    }

    func userInboundEventTriggered(context _: ChannelHandlerContext, event: Any) {
        if event is ChannelShouldQuiesceEvent {
            self.promise.succeed(())
        }
    }
}

final class QuiescingHelperTest: XCTestCase {
    func testShutdownIsImmediateWhenNoChannelsCollected() throws {
        let el = EmbeddedEventLoop()
        let channel = EmbeddedChannel(handler: nil, loop: el)
        // let's activate the server channel, nothing actually happens as this is an EmbeddedChannel
        XCTAssertNoThrow(try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 1)).wait())
        XCTAssertTrue(channel.isActive)
        let quiesce = ServerQuiescingHelper(group: el)
        _ = quiesce.makeServerChannelHandler(channel: channel)
        let p: EventLoopPromise<Void> = el.makePromise()
        quiesce.initiateShutdown(promise: p)
        XCTAssertNoThrow(try p.futureResult.wait())
        XCTAssertFalse(channel.isActive)
    }

    func testQuiesceUserEventReceivedOnShutdown() throws {
        let el = EmbeddedEventLoop()
        let allShutdownPromise: EventLoopPromise<Void> = el.makePromise()
        let serverChannel = EmbeddedChannel(handler: nil, loop: el)
        // let's activate the server channel, nothing actually happens as this is an EmbeddedChannel
        XCTAssertNoThrow(try serverChannel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 1)).wait())
        let quiesce = ServerQuiescingHelper(group: el)
        let collectionHandler = quiesce.makeServerChannelHandler(channel: serverChannel)
        XCTAssertNoThrow(try serverChannel.pipeline.syncOperations.addHandler(collectionHandler))
        var waitForFutures: [EventLoopFuture<Void>] = []
        var childChannels: [Channel] = []

        // add a bunch of channels
        for pretendPort in 1...128 {
            let waitForPromise: EventLoopPromise<Void> = el.makePromise()
            let channel = EmbeddedChannel(handler: WaitForQuiesceUserEvent(promise: waitForPromise), loop: el)
            // activate the child chan
            XCTAssertNoThrow(try channel.connect(to: .init(ipAddress: "1.2.3.4", port: pretendPort)).wait())
            waitForFutures.append(waitForPromise.futureResult)
            childChannels.append(channel)
            serverChannel.pipeline.fireChannelRead(channel)
        }
        // check that the server channel and all child channels are active before initiating the shutdown
        XCTAssertTrue(serverChannel.isActive)
        XCTAssertTrue(childChannels.allSatisfy { $0.isActive })
        quiesce.initiateShutdown(promise: allShutdownPromise)

        // check that the server channel is closed as the first thing
        XCTAssertFalse(serverChannel.isActive)

        el.run()
        // check that all the child channels have received the user event ...
        XCTAssertNoThrow(try EventLoopFuture<Void>.andAllSucceed(waitForFutures, on: el).wait() as Void)

        // ... and are still active
        XCTAssertTrue(childChannels.allSatisfy { $0.isActive })

        // now close all the child channels
        for childChannel in childChannels { childChannel.close(promise: nil) }
        el.run()

        XCTAssertTrue(childChannels.allSatisfy { !$0.isActive })

        // check that the shutdown has completed
        XCTAssertNoThrow(try allShutdownPromise.futureResult.wait())
    }

    func testQuiescingDoesNotSwallowCloseErrorsFromAcceptHandler() {
        // AcceptHandler is a `private class` so I can only implicitly get it by creating the real thing
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try group.syncShutdownGracefully())
        }

        let quiesce = ServerQuiescingHelper(group: group)

        struct DummyError: Error {}
        class MakeFirstCloseFailAndDontActuallyCloseHandler: ChannelOutboundHandler {
            typealias OutboundIn = Any

            var closes = 0

            func close(context: ChannelHandlerContext, mode: CloseMode, promise: EventLoopPromise<Void>?) {
                self.closes += 1
                if self.closes == 1 {
                    promise?.fail(DummyError())
                } else {
                    context.close(mode: mode, promise: promise)
                }
            }
        }

        let channel = try! ServerBootstrap(group: group).serverChannelInitializer { channel in
            channel.eventLoop.makeCompletedFuture {
                let sync = channel.pipeline.syncOperations
                try sync.addHandler(MakeFirstCloseFailAndDontActuallyCloseHandler(), position: .first)
                try sync.addHandler(quiesce.makeServerChannelHandler(channel: channel))
            }
        }.bind(host: "localhost", port: 0).wait()
        defer {
            XCTAssertNoThrow(try channel.close().wait())
        }

        let promise = channel.eventLoop.makePromise(of: Void.self)
        quiesce.initiateShutdown(promise: promise)
        XCTAssertThrowsError(try promise.futureResult.wait()) { error in
            XCTAssert(error is DummyError)
        }
    }

    /// verifying that the promise fails when goes out of scope for shutdown
    func testShutdownIsImmediateWhenPromiseDoesNotSucceed() throws {
        let el = EmbeddedEventLoop()

        let p: EventLoopPromise<Void> = el.makePromise()

        do {
            let quiesce = ServerQuiescingHelper(group: el)
            quiesce.initiateShutdown(promise: p)
        }
        XCTAssertThrowsError(try p.futureResult.wait()) { error in
            XCTAssertTrue(error is ServerQuiescingHelper.UnusedQuiescingHelperError)
        }
    }

    func testShutdown_whenAlreadyShutdown() throws {
        let el = EmbeddedEventLoop()
        let channel = EmbeddedChannel(handler: nil, loop: el)
        // let's activate the server channel, nothing actually happens as this is an EmbeddedChannel
        XCTAssertNoThrow(try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 1)).wait())
        XCTAssertTrue(channel.isActive)
        let quiesce = ServerQuiescingHelper(group: el)
        _ = quiesce.makeServerChannelHandler(channel: channel)
        let p1: EventLoopPromise<Void> = el.makePromise()
        quiesce.initiateShutdown(promise: p1)
        XCTAssertNoThrow(try p1.futureResult.wait())
        XCTAssertFalse(channel.isActive)

        let p2: EventLoopPromise<Void> = el.makePromise()
        quiesce.initiateShutdown(promise: p2)
        XCTAssertNoThrow(try p2.futureResult.wait())
    }

    func testShutdown_whenNoOpenChild() throws {
        let el = EmbeddedEventLoop()
        let channel = EmbeddedChannel(handler: nil, loop: el)
        // let's activate the server channel, nothing actually happens as this is an EmbeddedChannel
        XCTAssertNoThrow(try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 1)).wait())
        XCTAssertTrue(channel.isActive)
        let quiesce = ServerQuiescingHelper(group: el)
        _ = quiesce.makeServerChannelHandler(channel: channel)
        let p1: EventLoopPromise<Void> = el.makePromise()
        quiesce.initiateShutdown(promise: p1)
        el.run()
        XCTAssertNoThrow(try p1.futureResult.wait())
        XCTAssertFalse(channel.isActive)
    }

    func testChannelClose_whenRunning() throws {
        let el = EmbeddedEventLoop()
        let allShutdownPromise: EventLoopPromise<Void> = el.makePromise()
        let serverChannel = EmbeddedChannel(handler: nil, loop: el)
        // let's activate the server channel, nothing actually happens as this is an EmbeddedChannel
        XCTAssertNoThrow(try serverChannel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 1)).wait())
        let quiesce = ServerQuiescingHelper(group: el)
        let collectionHandler = quiesce.makeServerChannelHandler(channel: serverChannel)
        XCTAssertNoThrow(try serverChannel.pipeline.syncOperations.addHandler(collectionHandler))

        // let's one channels
        let eventCounterHandler = EventCounterHandler()
        let childChannel1 = EmbeddedChannel(handler: eventCounterHandler, loop: el)
        // activate the child channel
        XCTAssertNoThrow(try childChannel1.connect(to: .init(ipAddress: "1.2.3.4", port: 1)).wait())
        serverChannel.pipeline.fireChannelRead(childChannel1)

        // check that the server channel and channel are active before initiating the shutdown
        XCTAssertTrue(serverChannel.isActive)
        XCTAssertTrue(childChannel1.isActive)

        XCTAssertEqual(eventCounterHandler.userInboundEventTriggeredCalls, 0)

        // now close the first child channel
        childChannel1.close(promise: nil)
        el.run()

        // check that the server is active and child is not
        XCTAssertTrue(serverChannel.isActive)
        XCTAssertFalse(childChannel1.isActive)

        quiesce.initiateShutdown(promise: allShutdownPromise)
        el.run()

        // check that the server channel is closed as the first thing
        XCTAssertFalse(serverChannel.isActive)

        el.run()

        // check that the shutdown has completed
        XCTAssertNoThrow(try allShutdownPromise.futureResult.wait())
    }

    func testChannelAdded_whenShuttingDown() throws {
        let el = EmbeddedEventLoop()
        let allShutdownPromise: EventLoopPromise<Void> = el.makePromise()
        let serverChannel = EmbeddedChannel(handler: nil, loop: el)
        // let's activate the server channel, nothing actually happens as this is an EmbeddedChannel
        XCTAssertNoThrow(try serverChannel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 1)).wait())
        let quiesce = ServerQuiescingHelper(group: el)
        let collectionHandler = quiesce.makeServerChannelHandler(channel: serverChannel)
        XCTAssertNoThrow(try serverChannel.pipeline.syncOperations.addHandler(collectionHandler))

        // let's add one channel
        let waitForPromise1: EventLoopPromise<Void> = el.makePromise()
        let childChannel1 = EmbeddedChannel(handler: WaitForQuiesceUserEvent(promise: waitForPromise1), loop: el)
        // activate the child channel
        XCTAssertNoThrow(try childChannel1.connect(to: .init(ipAddress: "1.2.3.4", port: 1)).wait())
        serverChannel.pipeline.fireChannelRead(childChannel1)

        el.run()

        // check that the server and channel are running
        XCTAssertTrue(serverChannel.isActive)
        XCTAssertTrue(childChannel1.isActive)

        // let's shut down
        quiesce.initiateShutdown(promise: allShutdownPromise)

        // let's add one more channel
        let waitForPromise2: EventLoopPromise<Void> = el.makePromise()
        let childChannel2 = EmbeddedChannel(handler: WaitForQuiesceUserEvent(promise: waitForPromise2), loop: el)
        // activate the child channel
        XCTAssertNoThrow(try childChannel2.connect(to: .init(ipAddress: "1.2.3.4", port: 2)).wait())
        serverChannel.pipeline.fireChannelRead(childChannel2)
        el.run()

        // Check that we got all quiescing events
        XCTAssertNoThrow(try waitForPromise1.futureResult.wait() as Void)
        XCTAssertNoThrow(try waitForPromise2.futureResult.wait() as Void)

        // check that the server is closed and the children are running
        XCTAssertFalse(serverChannel.isActive)
        XCTAssertTrue(childChannel1.isActive)
        XCTAssertTrue(childChannel2.isActive)

        // let's close the children
        childChannel1.close(promise: nil)
        childChannel2.close(promise: nil)
        el.run()

        // check that everything is closed
        XCTAssertFalse(serverChannel.isActive)
        XCTAssertFalse(childChannel1.isActive)
        XCTAssertFalse(childChannel2.isActive)

        XCTAssertNoThrow(try allShutdownPromise.futureResult.wait() as Void)
    }

    func testChannelAdded_whenShutdown() throws {
        let el = EmbeddedEventLoop()
        let allShutdownPromise: EventLoopPromise<Void> = el.makePromise()
        let serverChannel = EmbeddedChannel(handler: nil, loop: el)
        // let's activate the server channel, nothing actually happens as this is an EmbeddedChannel
        XCTAssertNoThrow(try serverChannel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 1)).wait())
        let quiesce = ServerQuiescingHelper(group: el)
        let collectionHandler = quiesce.makeServerChannelHandler(channel: serverChannel)
        XCTAssertNoThrow(try serverChannel.pipeline.syncOperations.addHandler(collectionHandler))

        // check that the server is running
        XCTAssertTrue(serverChannel.isActive)

        // let's shut down
        quiesce.initiateShutdown(promise: allShutdownPromise)

        // check that the shutdown has completed
        XCTAssertNoThrow(try allShutdownPromise.futureResult.wait())

        // let's add one channel
        let childChannel1 = EmbeddedChannel(loop: el)
        // activate the child channel
        XCTAssertNoThrow(try childChannel1.connect(to: .init(ipAddress: "1.2.3.4", port: 1)).wait())
        serverChannel.pipeline.fireChannelRead(childChannel1)

        el.run()
    }
}
