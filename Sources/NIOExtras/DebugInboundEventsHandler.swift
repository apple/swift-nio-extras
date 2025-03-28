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

#if canImport(Darwin)
import Darwin
#elseif canImport(Musl)
@preconcurrency import Musl
#elseif canImport(Android)
@preconcurrency import Android
#else
@preconcurrency import Glibc
#endif

/// `ChannelInboundHandler` that prints all inbound events that pass through the pipeline by default,
/// overridable by providing your own closure for custom logging. See ``DebugOutboundEventsHandler`` for outbound events.
public class DebugInboundEventsHandler: ChannelInboundHandler {
    /// The type of the inbound data which is wrapped in `NIOAny`.
    public typealias InboundIn = Any
    /// The type of the inbound data which will be forwarded to the next `ChannelInboundHandler` in the `ChannelPipeline`.
    public typealias InboudOut = Any

    /// Enumeration of possible `ChannelHandler` events which can occur.
    public enum Event {
        /// Channel was registered.
        case registered
        /// Channel was unregistered.
        case unregistered
        /// Channel became active.
        case active
        /// Channel became inactive.
        case inactive
        /// Data was received.
        case read(data: NIOAny)
        ///  Current read loop finished.
        case readComplete
        /// Writability state of the channel changed.
        case writabilityChanged(isWritable: Bool)
        /// A user inbound event was received.
        case userInboundEventTriggered(event: Any)
        /// An error was caught.
        case errorCaught(Error)
    }

    var logger: (Event, ChannelHandlerContext) -> Void

    /// Initialiser.
    /// - Parameter logger: Method for logging events which occur.
    public init(logger: @escaping (Event, ChannelHandlerContext) -> Void = DebugInboundEventsHandler.defaultPrint) {
        self.logger = logger
    }

    /// Logs ``Event/registered`` to `logger`
    /// Called when the `Channel` has successfully registered with its `EventLoop` to handle I/O.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    public func channelRegistered(context: ChannelHandlerContext) {
        logger(.registered, context)
        context.fireChannelRegistered()
    }

    /// Logs ``Event/unregistered`` to `logger`
    /// Called when the `Channel` has unregistered from its `EventLoop`, and so will no longer be receiving I/O events.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    public func channelUnregistered(context: ChannelHandlerContext) {
        logger(.unregistered, context)
        context.fireChannelUnregistered()
    }

    /// Logs ``Event/active`` to `logger`
    /// Called when the `Channel` has become active, and is able to send and receive data.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    public func channelActive(context: ChannelHandlerContext) {
        logger(.active, context)
        context.fireChannelActive()
    }

    /// Logs ``Event/inactive`` to `logger`
    /// Called when the `Channel` has become inactive and is no longer able to send and receive data`.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    public func channelInactive(context: ChannelHandlerContext) {
        logger(.inactive, context)
        context.fireChannelInactive()
    }

    /// Logs ``Event/read(data:)`` to `logger`
    /// Called when some data has been read from the remote peer.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    ///     - data: The data read from the remote peer, wrapped in a `NIOAny`.
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        logger(.read(data: data), context)
        context.fireChannelRead(data)
    }

    /// Logs ``Event/readComplete`` to `logger`
    /// Called when the `Channel` has completed its current read loop, either because no more data is available
    /// to read from the transport at this time, or because the `Channel` needs to yield to the event loop to process
    /// other I/O events for other `Channel`s.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    public func channelReadComplete(context: ChannelHandlerContext) {
        logger(.readComplete, context)
        context.fireChannelReadComplete()
    }

    /// Logs ``Event/writabilityChanged(isWritable:)`` to `logger`
    /// The writability state of the `Channel` has changed, either because it has buffered more data than the writability
    /// high water mark, or because the amount of buffered data has dropped below the writability low water mark.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    public func channelWritabilityChanged(context: ChannelHandlerContext) {
        logger(.writabilityChanged(isWritable: context.channel.isWritable), context)
        context.fireChannelWritabilityChanged()
    }

    /// Logs ``Event/userInboundEventTriggered(event:)`` to `logger`
    /// Called when a user inbound event has been triggered.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    ///     - event: The event.
    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        logger(.userInboundEventTriggered(event: event), context)
        context.fireUserInboundEventTriggered(event)
    }

    /// Logs ``Event/errorCaught(_:)`` to `logger`
    /// An error was encountered earlier in the inbound `ChannelPipeline`.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    ///     - error: The `Error` that was encountered.
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger(.errorCaught(error), context)
        context.fireErrorCaught(error)
    }

    /// Print and flush a textual description of an ``Event``.
    /// - parameters:
    ///     - event: The ``Event`` to print.
    ///     - context: The context `event` was received in.
    public static func defaultPrint(event: Event, in context: ChannelHandlerContext) {
        let message: String
        switch event {
        case .registered:
            message = "Channel registered"
        case .unregistered:
            message = "Channel unregistered"
        case .active:
            message = "Channel became active"
        case .inactive:
            message = "Channel became inactive"
        case .read(let data):
            message = "Channel read \(data)"
        case .readComplete:
            message = "Channel completed reading"
        case .writabilityChanged(let isWritable):
            message = "Channel writability changed to \(isWritable)"
        case .userInboundEventTriggered(let event):
            message = "Channel user inbound event \(event) triggered"
        case .errorCaught(let error):
            message = "Channel caught error: \(error)"
        }
        print(message + " in \(context.name)")
        fflush(stdout)
    }
}

@available(*, unavailable)
extension DebugInboundEventsHandler: Sendable {}

@available(*, unavailable)
extension DebugInboundEventsHandler.Event: Sendable {}
