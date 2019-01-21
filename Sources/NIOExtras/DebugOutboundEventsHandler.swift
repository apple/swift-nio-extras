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

/// ChannelOutboundHandler that prints all outbound events that pass through the pipeline by default,
/// overridable by providing your own closure for custom logging. See DebugInboundEventsHandler for inbound events.
public class DebugOutboundEventsHandler: ChannelOutboundHandler {
    
    public typealias OutboundIn = Any
    public typealias OutboundOut = Any
    
    public enum Event {
        case register
        case bind(address: SocketAddress)
        case connect(address: SocketAddress)
        case write(data: NIOAny)
        case flush
        case read
        case close(mode: CloseMode)
        case triggerUserOutboundEvent(event: Any)
    }

    var logger: (Event, ChannelHandlerContext) -> ()
    
    public init(logger: @escaping (Event, ChannelHandlerContext) -> () = DebugOutboundEventsHandler.defaultPrint) {
        self.logger = logger
    }
    
    public func register(ctx: ChannelHandlerContext, promise: EventLoopPromise<Void>?) {
        logger(.register, ctx)
        ctx.register(promise: promise)
    }
    
    public func bind(ctx: ChannelHandlerContext, to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        logger(.bind(address: address), ctx)
        ctx.bind(to: address, promise: promise)
    }
    
    public func connect(ctx: ChannelHandlerContext, to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        logger(.connect(address: address), ctx)
        ctx.connect(to: address, promise: promise)
    }
    
    public func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        logger(.write(data: data), ctx)
        ctx.write(data, promise: promise)
    }
    
    public func flush(ctx: ChannelHandlerContext) {
        logger(.flush, ctx)
        ctx.flush()
    }
    
    public func read(ctx: ChannelHandlerContext) {
        logger(.read, ctx)
        ctx.read()
    }
    
    public func close(ctx: ChannelHandlerContext, mode: CloseMode, promise: EventLoopPromise<Void>?) {
        logger(.close(mode: mode), ctx)
        ctx.close(mode: mode, promise: promise)
    }
    
    public func triggerUserOutboundEvent(ctx: ChannelHandlerContext, event: Any, promise: EventLoopPromise<Void>?) {
        logger(.triggerUserOutboundEvent(event: event), ctx)
        ctx.triggerUserOutboundEvent(event, promise: promise)
    }

    public static func defaultPrint(event: Event, in ctx: ChannelHandlerContext) {
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
        print(message + " in \(ctx.name)")
    }
    
}
