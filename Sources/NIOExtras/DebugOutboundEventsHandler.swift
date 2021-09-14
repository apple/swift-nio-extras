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

#if os(macOS) || os(tvOS) || os(iOS) || os(watchOS)
import Darwin
#else
import Glibc
#endif

import NIOCore

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
    
    public func register(context: ChannelHandlerContext, promise: EventLoopPromise<Void>?) {
        logger(.register, context)
        context.register(promise: promise)
    }
    
    public func bind(context: ChannelHandlerContext, to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        logger(.bind(address: address), context)
        context.bind(to: address, promise: promise)
    }
    
    public func connect(context: ChannelHandlerContext, to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        logger(.connect(address: address), context)
        context.connect(to: address, promise: promise)
    }
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        logger(.write(data: data), context)
        context.write(data, promise: promise)
    }
    
    public func flush(context: ChannelHandlerContext) {
        logger(.flush, context)
        context.flush()
    }
    
    public func read(context: ChannelHandlerContext) {
        logger(.read, context)
        context.read()
    }
    
    public func close(context: ChannelHandlerContext, mode: CloseMode, promise: EventLoopPromise<Void>?) {
        logger(.close(mode: mode), context)
        context.close(mode: mode, promise: promise)
    }
    
    public func triggerUserOutboundEvent(context: ChannelHandlerContext, event: Any, promise: EventLoopPromise<Void>?) {
        logger(.triggerUserOutboundEvent(event: event), context)
        context.triggerUserOutboundEvent(event, promise: promise)
    }

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
