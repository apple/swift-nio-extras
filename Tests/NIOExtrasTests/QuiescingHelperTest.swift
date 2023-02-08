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

import XCTest
import NIOCore
import NIOEmbedded
import NIOPosix
import NIOTestUtils
@testable import NIOExtras

public class QuiescingHelperTest: XCTestCase {
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
        class WaitForQuiesceUserEvent: ChannelInboundHandler {
            typealias InboundIn = Never
            private let promise: EventLoopPromise<Void>

            init(promise: EventLoopPromise<Void>) {
                self.promise = promise
            }

            func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
                if event is ChannelShouldQuiesceEvent {
                    self.promise.succeed(())
                }
            }
        }

        let el = EmbeddedEventLoop()
        let allShutdownPromise: EventLoopPromise<Void> = el.makePromise()
        let serverChannel = EmbeddedChannel(handler: nil, loop: el)
        // let's activate the server channel, nothing actually happens as this is an EmbeddedChannel
        XCTAssertNoThrow(try serverChannel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 1)).wait())
        let quiesce = ServerQuiescingHelper(group: el)
        let collectionHandler = quiesce.makeServerChannelHandler(channel: serverChannel)
        XCTAssertNoThrow(try serverChannel.pipeline.addHandler(collectionHandler).wait())
        var waitForFutures: [EventLoopFuture<Void>] = []
        var childChannels: [Channel] = []

        // add a bunch of channels
        for pretendPort in 1...128 {
            let waitForPromise: EventLoopPromise<()> = el.makePromise()
            let channel = EmbeddedChannel(handler: WaitForQuiesceUserEvent(promise: waitForPromise), loop: el)
            // activate the child chan
            XCTAssertNoThrow(try channel.connect(to: .init(ipAddress: "1.2.3.4", port: pretendPort)).wait())
            waitForFutures.append(waitForPromise.futureResult)
            childChannels.append(channel)
            serverChannel.pipeline.fireChannelRead(NIOAny(channel))
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
        childChannels.forEach { $0.close(promise: nil) }
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
            channel.pipeline.addHandler(MakeFirstCloseFailAndDontActuallyCloseHandler(), position: .first).flatMap {
                channel.pipeline.addHandler(quiesce.makeServerChannelHandler(channel: channel))
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

    ///verifying that the promise fails when goes out of scope for shutdown
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
}
