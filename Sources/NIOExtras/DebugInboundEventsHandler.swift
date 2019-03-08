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
    
    public func channelRegistered(context: ChannelHandlerContext) {
        logger(.registered, context)
        context.fireChannelRegistered()
    }
    
    public func channelUnregistered(context: ChannelHandlerContext) {
        logger(.unregistered, context)
        context.fireChannelUnregistered()
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        logger(.active, context)
        context.fireChannelActive()
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        logger(.inactive, context)
        context.fireChannelInactive()
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        logger(.read(data: data), context)
        context.fireChannelRead(data)
    }
    
    public func channelReadComplete(context: ChannelHandlerContext) {
        logger(.readComplete, context)
        context.fireChannelReadComplete()
    }
    
    public func channelWritabilityChanged(context: ChannelHandlerContext) {
        logger(.writabilityChanged(isWritable: context.channel.isWritable), context)
        context.fireChannelWritabilityChanged()
    }
    
    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        logger(.userInboundEventTriggered(event: event), context)
        context.fireUserInboundEventTriggered(event)
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger(.errorCaught(error), context)
        context.fireErrorCaught(error)
    }
    
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
    }
    
}
