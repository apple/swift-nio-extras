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

import NIO

private enum ShutdownError: Error {
    case alreadyShutdown
}

/// Collects a number of channels that are open at the moment. To prevent races, `ChannelCollector` uses the
/// `EventLoop` of the server `Channel` that it gets passed to synchronise. It is important to call the
/// `channelAdded` method in the same event loop tick as the `Channel` is actually created.
private final class ChannelCollector {
    enum LifecycleState {
        case upAndRunning
        case shuttingDown
        case shutdownCompleted
    }
    private var openChannels: [ObjectIdentifier: Channel] = [:]
    private let serverChannel: Channel
    private var fullyShutdownPromise: EventLoopPromise<Void>? = nil
    private var lifecycleState = LifecycleState.upAndRunning

    private var eventLoop: EventLoop {
        return self.serverChannel.eventLoop
    }

    /// Initializes a `ChannelCollector` for `Channel`s accepted by `serverChannel`.
    init(serverChannel: Channel) {
        self.serverChannel = serverChannel
    }

    /// Add a channel to the `ChannelCollector`.
    ///
    /// - note: This must be called on `serverChannel.eventLoop`.
    ///
    /// - parameters:
    ///   - channel: The `Channel` to add to the `ChannelCollector`.
    func channelAdded(_ channel: Channel) throws {
        self.eventLoop.assertInEventLoop()

        guard self.lifecycleState != .shutdownCompleted else {
            channel.close(promise: nil)
            throw ShutdownError.alreadyShutdown
        }

        self.openChannels[ObjectIdentifier(channel)] = channel
    }

    private func shutdownCompleted() {
        self.eventLoop.assertInEventLoop()
        assert(self.lifecycleState == .shuttingDown)

        self.lifecycleState = .shutdownCompleted
        self.fullyShutdownPromise?.succeed(())
    }

    private func channelRemoved0(_ channel: Channel) {
        self.eventLoop.assertInEventLoop()
        precondition(self.openChannels.keys.contains(ObjectIdentifier(channel)),
                     "channel \(channel) not in ChannelCollector \(self.openChannels)")

        self.openChannels.removeValue(forKey: ObjectIdentifier(channel))
        if self.lifecycleState != .upAndRunning && self.openChannels.isEmpty {
            shutdownCompleted()
        }
    }

    /// Remove a previously added `Channel` from the `ChannelCollector`.
    ///
    /// - note: This method can be called from any thread.
    ///
    /// - parameters:
    ///    - channel: The `Channel` to be removed.
    func channelRemoved(_ channel: Channel) {
        if self.eventLoop.inEventLoop {
            self.channelRemoved0(channel)
        } else {
            self.eventLoop.execute {
                self.channelRemoved0(channel)
            }
        }
    }

    private func initiateShutdown0(promise: EventLoopPromise<Void>?) {
        self.eventLoop.assertInEventLoop()
        precondition(self.lifecycleState == .upAndRunning)

        self.lifecycleState = .shuttingDown

        if let promise = promise {
            if let alreadyExistingPromise = self.fullyShutdownPromise {
                alreadyExistingPromise.futureResult.cascade(to: promise)
            } else {
                self.fullyShutdownPromise = promise
            }
        }

        self.serverChannel.close().cascadeFailure(to: self.fullyShutdownPromise)

        for channel in self.openChannels.values {
            channel.eventLoop.execute {
                channel.pipeline.fireUserInboundEventTriggered(ChannelShouldQuiesceEvent())
            }
        }

        if self.openChannels.isEmpty {
            shutdownCompleted()
        }
    }

    /// Initiate the shutdown fulfilling `promise` when all the previously registered `Channel`s have been closed.
    ///
    /// - parameters:
    ///    - promise: The `EventLoopPromise` to fulfill when the shutdown of all previously registered `Channel`s has been completed.
    func initiateShutdown(promise: EventLoopPromise<Void>?) {
        if self.serverChannel.eventLoop.inEventLoop {
            self.serverChannel.pipeline.fireUserInboundEventTriggered(ChannelShouldQuiesceEvent())
        } else {
            self.eventLoop.execute {
                self.serverChannel.pipeline.fireUserInboundEventTriggered(ChannelShouldQuiesceEvent())
            }
        }

        if self.eventLoop.inEventLoop {
            self.initiateShutdown0(promise: promise)
        } else {
            self.eventLoop.execute {
                self.initiateShutdown0(promise: promise)
            }
        }
    }
}

/// A `ChannelHandler` that adds all channels that it receives through the `ChannelPipeline` to a `ChannelCollector`.
///
/// - note: This is only useful to be added to a server `Channel` in `ServerBootstrap.serverChannelInitializer`.
private final class CollectAcceptedChannelsHandler: ChannelInboundHandler {
    typealias InboundIn = Channel

    private let channelCollector: ChannelCollector

    /// Initialise with a `ChannelCollector` to add the received `Channels` to.
    init(channelCollector: ChannelCollector) {
        self.channelCollector = channelCollector
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is ChannelShouldQuiesceEvent {
            // ServerQuiescingHelper will close us anyway
            return
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channel = self.unwrapInboundIn(data)
        do {
            try self.channelCollector.channelAdded(channel)
            let closeFuture = channel.closeFuture
            closeFuture.whenComplete { (_: Result<(), Error>) in
                self.channelCollector.channelRemoved(channel)
            }
            context.fireChannelRead(data)
        } catch ShutdownError.alreadyShutdown {
            channel.close(promise: nil)
        } catch {
            fatalError("unexpected error \(error)")
        }
    }
}

/// Helper that can be used to orchestrate the quiescing of a server `Channel` and all the child `Channel`s that are
/// open at a given point in time.
///
/// `ServerQuiescingHelper` makes it easy to collect all child `Channel`s that a given server `Channel` accepts. When
/// the quiescing period starts (that is when `ServerQuiescingHelper.initiateShutdown` is invoked), it will perform the
/// following actions:
///
/// 1. close the server `Channel` so no further connections get accepted
/// 2. send a `ChannelShouldQuiesceEvent` user event to all currently still open child `Channel`s
/// 3. after all previously open child `Channel`s have closed, notify the `EventLoopPromise` that was passed to `shutdown`.
///
/// Example use:
///
///     let group = MultiThreadedEventLoopGroup(numThreads: [...])
///     let quiesce = ServerQuiescingHelper(group: group)
///     let serverChannel = try ServerBootstrap(group: group)
///         .serverChannelInitializer { channel in
///             // add the collection handler so all accepted child channels get collected
///             channel.pipeline.add(handler: quiesce.makeServerChannelHandler(channel: channel))
///         }
///         // further bootstrap configuration
///         .bind([...])
///         .wait()
///     // [...]
///     let fullyShutdownPromise: EventLoopPromise<Void> = group.next().newPromise()
///     // initiate the shutdown
///     quiesce.initiateShutdown(promise: fullyShutdownPromise)
///     // wait for the shutdown to complete
///     try fullyShutdownPromise.futureResult.wait()
///
public final class ServerQuiescingHelper {
    private let channelCollectorPromise: EventLoopPromise<ChannelCollector>

    /// Initialize with a given `EventLoopGroup`.
    ///
    /// - parameters:
    ///   - group: The `EventLoopGroup` to use to allocate new promises and the like.
    public init(group: EventLoopGroup) {
        self.channelCollectorPromise = group.next().makePromise()
    }

    /// Create the `ChannelHandler` for the server `channel` to collect all accepted child `Channel`s.
    ///
    /// - parameters:
    ///   - channel: The server `Channel` whose child `Channel`s to collect
    /// - returns: a `ChannelHandler` that the user must add to the server `Channel`s pipeline
    public func makeServerChannelHandler(channel: Channel) -> ChannelHandler {
        let collector = ChannelCollector(serverChannel: channel)
        self.channelCollectorPromise.succeed(collector)
        return CollectAcceptedChannelsHandler(channelCollector: collector)
    }

    /// Initiate the shutdown. The following actions will be performed:
    ///
    /// 1. close the server `Channel` so no further connections get accepted
    /// 2. send a `ChannelShouldQuiesceEvent` user event to all currently still open child `Channel`s
    /// 3. after all previously open child `Channel`s have closed, notify `promise`
    ///
    /// - parameters:
    ///   - promise: The `EventLoopPromise` that will be fulfilled when the shutdown is complete.
    public func initiateShutdown(promise: EventLoopPromise<Void>?) {
        let f = self.channelCollectorPromise.futureResult.map { channelCollector in
            channelCollector.initiateShutdown(promise: promise)
        }
        if let promise = promise {
            f.cascadeFailure(to: promise)
        }
    }
}
