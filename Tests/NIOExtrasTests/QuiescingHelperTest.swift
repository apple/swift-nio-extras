//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import XCTest
import NIO
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
        for _ in 0..<128 {
            let waitForPromise: EventLoopPromise<()> = el.makePromise()
            let channel = EmbeddedChannel(handler: WaitForQuiesceUserEvent(promise: waitForPromise), loop: el)
            waitForFutures.append(waitForPromise.futureResult)
            childChannels.append(channel)
            serverChannel.pipeline.fireChannelRead(NIOAny(channel))
        }
        // check that the server channel is active before initiating the shutdown
        XCTAssertTrue(serverChannel.isActive)
        quiesce.initiateShutdown(promise: allShutdownPromise)

        // check that the server channel is closed as the first thing
        XCTAssertFalse(serverChannel.isActive)

        el.run()
        // check that all the child channels have received the user event
        XCTAssertNoThrow(try EventLoopFuture<Void>.andAllSucceed(waitForFutures, on: el).wait() as Void)

        // now close all the child channels
        childChannels.forEach { $0.close(promise: nil) }
        el.run()

        // check that the shutdown has completed
        XCTAssertNoThrow(try allShutdownPromise.futureResult.wait())
    }
}
