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

/// Data was unexpectedly written or read before the SOCKS proxy
/// connection has been fully established.
public struct ProxyNotEstablished: Error {
    
}

/// Connects to a SOCKS server to establish a proxied connection
/// to a host. This handler should be inserted at the beginning of a
/// channel's pipeline.
public class SOCKSClientHandler: ChannelDuplexHandler {
    
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    
    private let authenticationDelegate: SOCKSClientAuthenticationDelegate
    private let supportedAuthenticationMethods: [AuthenticationMethod]
    private let targetAddress: AddressType
    
    private var state: ClientStateMachine
    private var buffered: ByteBuffer
    
    private var bufferedWrites: [(NIOAny, EventLoopPromise<Void>?)] = []
    
    public init(
        supportedAuthenticationMethods: [AuthenticationMethod],
        targetAddress: AddressType,
        authenticationDelegate: SOCKSClientAuthenticationDelegate
    ) {
        precondition(supportedAuthenticationMethods.count > 0,
                     "At least one supported authentication method required.")
        precondition(supportedAuthenticationMethods.count <= 255,
                     "There can't be more than 255 authentication methods listed.")
        self.supportedAuthenticationMethods = supportedAuthenticationMethods
        self.state = ClientStateMachine()
        self.buffered = ByteBuffer()
        self.targetAddress = targetAddress
        self.authenticationDelegate = authenticationDelegate
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        self.handleAction(self.state.connectionEstablished(), context: context)
    }
    
    public func handlerAdded(context: ChannelHandlerContext) {
        if context.channel.isActive {
            guard self.state.shouldBeginHandshake else {
                return
            }
            self.handleAction(self.state.connectionEstablished(), context: context)
        }
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        
        // if we've established the connection then forward on the data
        guard !self.state.proxyEstablished else {
            context.fireChannelRead(data)
            return
        }
        
        var buffer = self.unwrapInboundIn(data)
        self.buffered.writeBuffer(&buffer)
        let save = self.buffered
        do {
            let action = try self.state.receiveBuffer(&self.buffered)
            switch action {
            case .waitForMoreData:
                self.buffered = save
            default:
                self.handleAction(action, context: context)
            }
        } catch {
            context.fireErrorCaught(error)
            context.close(mode: .all, promise: nil)
        }
    }
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        guard self.state.proxyEstablished else {
            self.bufferedWrites.append((data, promise))
            return
        }
        context.write(data, promise: nil)
    }
    
}

extension SOCKSClientHandler {
    
    func startHandshake(context: ChannelHandlerContext) {
        
        // if the handshake has already begun
        // or completed, then don't start it again
        guard self.state.shouldBeginHandshake else {
            return
        }
        
        let greeting = ClientGreeting(
            methods: self.supportedAuthenticationMethods
        )
        let capacity = 2 + self.supportedAuthenticationMethods.count
        var buffer = context.channel.allocator.buffer(capacity: capacity)
        buffer.writeClientGreeting(greeting)
        
        do {
            try self.state.sendClientGreeting(greeting)
        } catch {
            context.fireErrorCaught(error)
            return
        }
        
        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
        context.fireChannelActive()
    }
    
    func handleAction(_ action: ClientAction, context: ChannelHandlerContext) {
        do {
            switch action {
            case .sendGreeting:
                self.startHandshake(context: context)
            case .authenticateIfNeeded(let method):
                try self.handleActionAuthenticateIfNeeded(method: method, context: context)
            case .sendRequest:
                self.handleActionSendRequest(context: context)
            case .proxyEstablished:
                self.handleActionProxyEstablished(context: context)
            case.none, .waitForMoreData:
                break
            }
        } catch {
            context.fireErrorCaught(error)
        }
    }
    
    func handleActionAuthenticateIfNeeded(method: AuthenticationMethod, context: ChannelHandlerContext) throws {
        let result = try self.authenticationDelegate.serverSelectedAuthenticationMethod(method)
        switch result {
        case .authenticationComplete:
            self.handleAction(try self.state.authenticationComplete(), context: context)
            break
        case .authenticationFailed:
            break
        case .needsMoreData:
            break
        case .respond(let bytes):
            context.writeAndFlush(self.wrapOutboundOut(bytes), promise: nil)
        }
    }
    
    func handleActionProxyEstablished(context: ChannelHandlerContext) {
        // for some reason we have extra bytes
        // so let's send them down the pipe
        if self.buffered.readableBytes > 0 {
            let data = self.wrapInboundOut(self.buffered)
            context.fireChannelRead(data)
        }
        
        // If we have any buffered writes then now
        // we can send them.
        for (data, promise) in self.bufferedWrites {
            context.write(data, promise: promise)
        }
        self.bufferedWrites = []
    }
    
    func handleActionSendRequest(context: ChannelHandlerContext) {
        let request = ClientRequest(command: .connect, addressType: self.targetAddress)
        do {
            try self.state.sendClientRequest(request)
        } catch {
            context.fireErrorCaught(error)
        }
        let capacity = 6 + self.targetAddress.size
        var buffer = context.channel.allocator.buffer(capacity: capacity)
        buffer.writeClientRequest(request)
        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
    }
    
}
