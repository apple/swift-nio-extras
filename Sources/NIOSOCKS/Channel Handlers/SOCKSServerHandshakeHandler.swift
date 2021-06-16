//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO

/// Add this handshake handler to the front of your channel, closest to the network.
/// The handler will receive bytes from the network and run them through a state machine
/// and parser to enforce SOCKSv5 protocol correctness. Inbound bytes will by parsed into
/// `ClientMessage` for downstream consumption. Send `ServerMessage` to this
/// handler.
public final class SOCKSServerHandshakeHandler: ChannelDuplexHandler, RemovableChannelHandler {
    
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ClientMessage
    public typealias OutboundIn = ServerMessage
    public typealias OutboundOut = ByteBuffer
    
    var inboundBuffer: ByteBuffer?
    var stateMachine: ServerStateMachine
    
    public init() {
        self.stateMachine = ServerStateMachine()
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        
        if self.stateMachine.proxyEstablished {
            context.fireChannelRead(data)
            return
        }
        
        var message = self.unwrapInboundIn(data)
        self.inboundBuffer.setOrWriteBuffer(&message)
        do {
            // safe to bang inbound buffer, it's always written above
            guard let message = try self.stateMachine.receiveBuffer(&self.inboundBuffer!) else {
                return // do nothing, we've buffered the data
            }
            context.fireChannelRead(self.wrapInboundOut(message))
        } catch {
            context.fireErrorCaught(error)
        }
    }
    
    public func handlerAdded(context: ChannelHandlerContext) {
        do {
            try self.stateMachine.connectionEstablished()
        } catch {
            context.fireErrorCaught(error)
        }
    }
    
    public func handlerRemoved(context: ChannelHandlerContext) {
        guard let buffer = self.inboundBuffer else {
            return
        }
        context.fireChannelRead(.init(buffer))
    }
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        do {
            let message = self.unwrapOutboundIn(data)
            switch message {
            case .selectedAuthenticationMethod(let method):
                try self.handleWriteSelectedAuthenticationMethod(method, context: context, promise: promise)
            case .response(let response):
                try self.handleWriteResponse(response, context: context, promise: promise)
            case .authenticationData(let data):
                try self.handleWriteData(data, context: context, promise: promise)
            case .authenticationComplete:
                try self.handleAuthenticationComplete(context: context, promise: promise)
            }
        } catch {
            context.fireErrorCaught(error)
            promise?.fail(error)
        }
    }
    
    private func handleWriteSelectedAuthenticationMethod(
        _ method: SelectedAuthenticationMethod, context: ChannelHandlerContext, promise: EventLoopPromise<Void>?) throws {
        try stateMachine.sendAuthenticationMethod(method)
        var buffer = context.channel.allocator.buffer(capacity: 16)
        buffer.writeMethodSelection(method)
        context.write(self.wrapOutboundOut(buffer), promise: promise)
    }
    
    private func handleWriteResponse(
        _ response: SOCKSResponse, context: ChannelHandlerContext, promise: EventLoopPromise<Void>?) throws {
        try stateMachine.sendServerResponse(response)
        var buffer = context.channel.allocator.buffer(capacity: 16)
        buffer.writeServerResponse(response)
        context.write(self.wrapOutboundOut(buffer), promise: promise)
    }
    
    private func handleWriteData(_ data :ByteBuffer, context: ChannelHandlerContext, promise: EventLoopPromise<Void>?) throws {
        context.write(self.wrapOutboundOut(data), promise: promise)
    }
    
    private func handleAuthenticationComplete(context: ChannelHandlerContext, promise: EventLoopPromise<Void>?) throws {
        try stateMachine.authenticationComplete()
        promise?.succeed(())
    }
    
}
