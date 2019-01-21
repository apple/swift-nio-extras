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

/// ChannelInboundHandler that prints all inbound events that pass through the pipeline by default,
/// overridable by providing your own closure for custom logging. See DebugOutboundEventsHandler for outbound events.
public class DebugInboundEventsHandler: ChannelInboundHandler {
    
    public typealias InboundIn = Any
    public typealias InboudOut = Any
    
    public enum Event {
        case registered
        case unregistered
        case active
        case inactive
        case read(data: NIOAny)
        case readComplete
        case writabilityChanged(isWritable: Bool)
        case userInboundEventTriggered(event: Any)
        case errorCaught(Error)
    }
    
    var logger: (Event, ChannelHandlerContext) -> ()
    
    public init(logger: @escaping (Event, ChannelHandlerContext) -> () = DebugInboundEventsHandler.defaultPrint) {
        self.logger = logger
    }
    
    public func channelRegistered(ctx: ChannelHandlerContext) {
        logger(.registered, ctx)
        ctx.fireChannelRegistered()
    }
    
    public func channelUnregistered(ctx: ChannelHandlerContext) {
        logger(.unregistered, ctx)
        ctx.fireChannelUnregistered()
    }
    
    public func channelActive(ctx: ChannelHandlerContext) {
        logger(.active, ctx)
        ctx.fireChannelActive()
    }
    
    public func channelInactive(ctx: ChannelHandlerContext) {
        logger(.inactive, ctx)
        ctx.fireChannelInactive()
    }
    
    public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        logger(.read(data: data), ctx)
        ctx.fireChannelRead(data)
    }
    
    public func channelReadComplete(ctx: ChannelHandlerContext) {
        logger(.readComplete, ctx)
        ctx.fireChannelReadComplete()
    }
    
    public func channelWritabilityChanged(ctx: ChannelHandlerContext) {
        logger(.writabilityChanged(isWritable: ctx.channel.isWritable), ctx)
        ctx.fireChannelWritabilityChanged()
    }
    
    public func userInboundEventTriggered(ctx: ChannelHandlerContext, event: Any) {
        logger(.userInboundEventTriggered(event: event), ctx)
        ctx.fireUserInboundEventTriggered(event)
    }
    
    public func errorCaught(ctx: ChannelHandlerContext, error: Error) {
        logger(.errorCaught(error), ctx)
        ctx.fireErrorCaught(error)
    }
    
    public static func defaultPrint(event: Event, in ctx: ChannelHandlerContext) {
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
        print(message + " in \(ctx.name)")
    }
    
}
