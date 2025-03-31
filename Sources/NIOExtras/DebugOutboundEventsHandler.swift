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

/// ChannelOutboundHandler that prints all outbound events that pass through the pipeline by default,
/// overridable by providing your own closure for custom logging. See ``DebugInboundEventsHandler`` for inbound events.
public class DebugOutboundEventsHandler: ChannelOutboundHandler {
    /// The type of the outbound data which is wrapped in `NIOAny`.
    public typealias OutboundIn = Any
    /// The type of the outbound data which will be forwarded to the next `ChannelOutboundHandler` in the `ChannelPipeline`.
    public typealias OutboundOut = Any

    /// All possible outbound events which could occur.
    public enum Event {
        /// `Channel` registered for I/O events.
        case register
        /// Bound to a `SocketAddress`
        case bind(address: SocketAddress)
        /// Connected to an address.
        case connect(address: SocketAddress)
        /// Write operation.
        case write(data: NIOAny)
        /// Pending writes flushed.
        case flush
        /// Ready to read more data.
        case read
        /// Close the channel.
        case close(mode: CloseMode)
        /// User outbound event triggered.
        case triggerUserOutboundEvent(event: Any)
    }

    var logger: (Event, ChannelHandlerContext) -> Void

    /// Initialiser.
    /// - parameters:
    ///     - logger: Method for logging events which happen.
    public init(logger: @escaping (Event, ChannelHandlerContext) -> Void = DebugOutboundEventsHandler.defaultPrint) {
        self.logger = logger
    }

    /// Logs ``Event/register`` to `logger`
    /// Called to request that the `Channel` register itself for I/O events with its `EventLoop`.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    ///     - promise: The `EventLoopPromise` which should be notified once the operation completes, or nil if no notification should take place.
    public func register(context: ChannelHandlerContext, promise: EventLoopPromise<Void>?) {
        logger(.register, context)
        context.register(promise: promise)
    }

    /// Logs ``Event/bind(address:)`` to `logger`
    /// Called to request that the `Channel` bind to a specific `SocketAddress`.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    ///     - address: The `SocketAddress` to which this `Channel` should bind.
    ///     - promise: The `EventLoopPromise` which should be notified once the operation completes, or nil if no notification should take place.
    public func bind(context: ChannelHandlerContext, to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        logger(.bind(address: address), context)
        context.bind(to: address, promise: promise)
    }

    /// Logs ``Event/connect(address:)`` to `logger`
    /// Called to request that the `Channel` connect to a given `SocketAddress`.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    ///     - address: The `SocketAddress` to which the the `Channel` should connect.
    ///     - promise: The `EventLoopPromise` which should be notified once the operation completes, or nil if no notification should take place.
    public func connect(context: ChannelHandlerContext, to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        logger(.connect(address: address), context)
        context.connect(to: address, promise: promise)
    }

    /// Logs ``Event/write(data:)`` to `logger`
    /// Called to request a write operation.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    ///     - data: The data to write through the `Channel`, wrapped in a `NIOAny`.
    ///     - promise: The `EventLoopPromise` which should be notified once the operation completes, or nil if no notification should take place.
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        logger(.write(data: data), context)
        context.write(data, promise: promise)
    }

    /// Logs ``Event/flush`` to `logger`
    /// Called to request that the `Channel` flush all pending writes. The flush operation will try to flush out all previous written messages
    /// that are pending.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    public func flush(context: ChannelHandlerContext) {
        logger(.flush, context)
        context.flush()
    }

    /// Logs ``Event/read`` to `logger`
    /// Called to request that the `Channel` perform a read when data is ready. The read operation will signal that we are ready to read more data.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    public func read(context: ChannelHandlerContext) {
        logger(.read, context)
        context.read()
    }

    /// Logs ``Event/close(mode:)`` to `logger`
    /// Called to request that the `Channel` close itself down`.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    ///     - mode: The `CloseMode` to apply
    ///     - promise: The `EventLoopPromise` which should be notified once the operation completes, or nil if no notification should take place.
    public func close(context: ChannelHandlerContext, mode: CloseMode, promise: EventLoopPromise<Void>?) {
        logger(.close(mode: mode), context)
        context.close(mode: mode, promise: promise)
    }

    /// Logs ``Event/triggerUserOutboundEvent(event:)`` to `logger`
    /// Called when an user outbound event is triggered.
    /// - parameters:
    ///     - context: The `ChannelHandlerContext` which this `ChannelHandler` belongs to.
    ///     - event: The triggered event.
    ///     - promise: The `EventLoopPromise` which should be notified once the operation completes, or nil if no notification should take place.
    public func triggerUserOutboundEvent(context: ChannelHandlerContext, event: Any, promise: EventLoopPromise<Void>?) {
        logger(.triggerUserOutboundEvent(event: event), context)
        context.triggerUserOutboundEvent(event, promise: promise)
    }

    /// Print textual event description to stdout.
    ///  - parameters:
    ///      - event: The ``Event`` to print.
    ///      - context: The context the event occured in.
    public static func defaultPrint(event: Event, in context: ChannelHandlerContext) {
        let message: String
        switch event {
        case .register:
            message = "Registering channel"
        case .bind(let address):
            message = "Binding to \(address)"
        case .connect(let address):
            message = "Connecting to \(address)"
        case .write(let data):
            message = "Writing \(data)"
        case .flush:
            message = "Flushing"
        case .read:
            message = "Reading"
        case .close(let mode):
            message = "Closing with mode \(mode)"
            print()
        case .triggerUserOutboundEvent(let event):
            message = "Triggering user outbound event: { \(event) }"
        }
        print(message + " in \(context.name)")
        fflush(stdout)
    }
}

@available(*, unavailable)
extension DebugOutboundEventsHandler: Sendable {}

@available(*, unavailable)
extension DebugOutboundEventsHandler.Event: Sendable {}
