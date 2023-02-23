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

private enum ShutdownError: Error {
    case alreadyShutdown
}

/// Collects a number of channels that are open at the moment. To prevent races, `ChannelCollector` uses the
/// `EventLoop` of the server `Channel` that it gets passed to synchronise. It is important to call the
/// `channelAdded` method in the same event loop tick as the `Channel` is actually created.
private final class ChannelCollector {
    enum LifecycleState {
        case upAndRunning(
            openChannels: [ObjectIdentifier: Channel],
            serverChannel: Channel
        )
        case shuttingDown(
            openChannels: [ObjectIdentifier: Channel],
            fullyShutdownPromise: EventLoopPromise<Void>
        )
        case shutdownCompleted
    }

    private var lifecycleState: LifecycleState

    private let eventLoop: EventLoop

    /// Initializes a `ChannelCollector` for `Channel`s accepted by `serverChannel`.
    init(serverChannel: Channel) {
        self.eventLoop = serverChannel.eventLoop
        self.lifecycleState = .upAndRunning(openChannels: [:], serverChannel: serverChannel)
    }

    /// Add a channel to the `ChannelCollector`.
    ///
    /// - note: This must be called on `serverChannel.eventLoop`.
    ///
    /// - parameters:
    ///   - channel: The `Channel` to add to the `ChannelCollector`.
    func channelAdded(_ channel: Channel) throws {
        self.eventLoop.assertInEventLoop()

        switch self.lifecycleState {
        case .upAndRunning(var openChannels, let serverChannel):
            openChannels[ObjectIdentifier(channel)] = channel
            self.lifecycleState = .upAndRunning(openChannels: openChannels, serverChannel: serverChannel)

        case .shuttingDown(var openChannels, let fullyShutdownPromise):
            openChannels[ObjectIdentifier(channel)] = channel
            channel.eventLoop.execute {
                channel.pipeline.fireUserInboundEventTriggered(ChannelShouldQuiesceEvent())
            }
            self.lifecycleState = .shuttingDown(openChannels: openChannels, fullyShutdownPromise: fullyShutdownPromise)

        case .shutdownCompleted:
            channel.close(promise: nil)
            throw ShutdownError.alreadyShutdown
        }
    }

    private func shutdownCompleted() {
        self.eventLoop.assertInEventLoop()

        switch self.lifecycleState {
        case .upAndRunning:
            preconditionFailure("This can never happen because we transition to shuttingDown first")

        case .shuttingDown(_, let fullyShutdownPromise):
            self.lifecycleState = .shutdownCompleted
            fullyShutdownPromise.succeed(())

        case .shutdownCompleted:
            preconditionFailure("We should only complete the shutdown once")
        }
    }

    private func channelRemoved0(_ channel: Channel) {
        self.eventLoop.assertInEventLoop()

        switch self.lifecycleState {
        case .upAndRunning(var openChannels, let serverChannel):
            let removedChannel = openChannels.removeValue(forKey: ObjectIdentifier(channel))

            precondition(removedChannel != nil, "channel \(channel) not in ChannelCollector \(openChannels)")

            self.lifecycleState = .upAndRunning(openChannels: openChannels, serverChannel: serverChannel)

        case .shuttingDown(var openChannels, let fullyShutdownPromise):
            let removedChannel = openChannels.removeValue(forKey: ObjectIdentifier(channel))

            precondition(removedChannel != nil, "channel \(channel) not in ChannelCollector \(openChannels)")

            if openChannels.isEmpty {
                self.shutdownCompleted()
            } else {
                self.lifecycleState = .shuttingDown(openChannels: openChannels, fullyShutdownPromise: fullyShutdownPromise)
            }

        case .shutdownCompleted:
            preconditionFailure("We should not have channels removed after transitioned to completed")
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

        switch self.lifecycleState {
        case .upAndRunning(let openChannels, let serverChannel):
            let fullyShutdownPromise = promise ?? serverChannel.eventLoop.makePromise(of: Void.self)

            self.lifecycleState = .shuttingDown(openChannels: openChannels, fullyShutdownPromise: fullyShutdownPromise)

            serverChannel.pipeline.fireUserInboundEventTriggered(ChannelShouldQuiesceEvent())
            serverChannel.close().cascadeFailure(to: fullyShutdownPromise)

            for channel in openChannels.values {
                channel.eventLoop.execute {
                    channel.pipeline.fireUserInboundEventTriggered(ChannelShouldQuiesceEvent())
                }
            }

            if openChannels.isEmpty {
                self.shutdownCompleted()
            }

        case .shuttingDown(_, let fullyShutdownPromise):
            fullyShutdownPromise.futureResult.cascade(to: promise)

        case .shutdownCompleted:
            promise?.succeed(())
        }
    }

    /// Initiate the shutdown fulfilling `promise` when all the previously registered `Channel`s have been closed.
    ///
    /// - parameters:
    ///    - promise: The `EventLoopPromise` to fulfil when the shutdown of all previously registered `Channel`s has been completed.
    func initiateShutdown(promise: EventLoopPromise<Void>?) {
        if self.eventLoop.inEventLoop {
            self.initiateShutdown0(promise: promise)
        } else {
            self.eventLoop.execute {
                self.initiateShutdown0(promise: promise)
            }
        }
    }
}

extension ChannelCollector: @unchecked Sendable {}

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
            closeFuture.whenComplete { (_: Result<Void, Error>) in
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
/// ``ServerQuiescingHelper`` makes it easy to collect all child `Channel`s that a given server `Channel` accepts. When
/// the quiescing period starts (that is when ``initiateShutdown(promise:)`` is invoked), it will perform the
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
    /// The `ServerQuiescingHelper` was never used to create a channel handler.
    public struct UnusedQuiescingHelperError: Error {}
    private let channelCollectorPromise: EventLoopPromise<ChannelCollector>

    /// Initialize with a given `EventLoopGroup`.
    ///
    /// - parameters:
    ///   - group: The `EventLoopGroup` to use to allocate new promises and the like.
    public init(group: EventLoopGroup) {
        self.channelCollectorPromise = group.next().makePromise()
    }

    deinit {
        self.channelCollectorPromise.fail(UnusedQuiescingHelperError())
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

    /// Initiate the shutdown.
    ///
    /// The following actions will be performed:
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

extension ServerQuiescingHelper: Sendable {}
