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

public enum ClientMessage: Hashable {
    case greeting(ClientGreeting)
    case request(SOCKSRequest)
    case data(ByteBuffer)
}

public enum ServerMessage: Hashable {
    case selectedAuthenticationMethod(SelectedAuthenticationMethod)
    case response(SOCKSResponse)
    case data(ByteBuffer)
    case authenticationComplete
}

extension ByteBuffer {
    
    @discardableResult mutating func writeServerMessage(_ message: ServerMessage) -> Int {
        switch message {
        case .selectedAuthenticationMethod(let method):
            return self.writeMethodSelection(method)
        case .response(let response):
            return self.writeServerResponse(response)
        case .data(var buffer):
            return self.writeBuffer(&buffer)
        case .authenticationComplete:
            return 0
        }
    }
    
}

public final class SOCKSServerHandshakeHandler: ChannelDuplexHandler {
    
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
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        do {
            let message = self.unwrapOutboundIn(data)
            switch message {
            case .selectedAuthenticationMethod(let method):
                try self.handleWriteSelectedAuthenticationMethod(method, context: context, promise: promise)
            case .response(let response):
                try self.handleWriteResponse(response, context: context, promise: promise)
            case .data(let data):
                try self.handleWriteData(data, context: context, promise: promise)
            case .authenticationComplete:
                try self.handleAuthenticationComplete(context: context, promise: promise)
            }
        } catch {
            context.fireErrorCaught(error)
            promise?.fail(error)
        }
    }
    
    func handleWriteSelectedAuthenticationMethod(
        _ method: SelectedAuthenticationMethod, context: ChannelHandlerContext, promise: EventLoopPromise<Void>?) throws {
        var buffer = context.channel.allocator.buffer(capacity: 16)
        buffer.writeMethodSelection(method)
        try stateMachine.sendAuthenticationMethod(method)
        context.write(self.wrapOutboundOut(buffer), promise: promise)
    }
    
    func handleWriteResponse(
        _ response: SOCKSResponse, context: ChannelHandlerContext, promise: EventLoopPromise<Void>?) throws {
        var buffer = context.channel.allocator.buffer(capacity: 16)
        buffer.writeServerResponse(response)
        try stateMachine.sendServerResponse(response)
        context.write(self.wrapOutboundOut(buffer), promise: promise)
    }
    
    func handleWriteData(_ data :ByteBuffer, context: ChannelHandlerContext, promise: EventLoopPromise<Void>?) throws {
        
    }
    
    func handleAuthenticationComplete(context: ChannelHandlerContext, promise: EventLoopPromise<Void>?) throws {
        try stateMachine.authenticationComplete()
        promise?.succeed(())
    }
    
}
