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
    
    public let supportedAuthenticationMethods: [AuthenticationMethod]
    public let targetAddress: AddressType
    public let targetPort: UInt16
    
    private var state: ClientStateMachine
    private var buffered: ByteBuffer
    
    public init(supportedAuthenticationMethods: [AuthenticationMethod], targetAddress: AddressType, targetPort: UInt16) {
        precondition(supportedAuthenticationMethods.count > 0,
                     "At least one supported authentication method required.")
        precondition(supportedAuthenticationMethods.count <= 255,
                     "There can't be more than 255 authentication methods listed.")
        self.supportedAuthenticationMethods = supportedAuthenticationMethods
        self.state = ClientStateMachine()
        self.buffered = ByteBuffer()
        self.targetAddress = targetAddress
        self.targetPort = targetPort
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        context.fireChannelInactive()
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        let greeting = ClientGreeting(
            methods: self.supportedAuthenticationMethods
        )
        let capacity = 2 + self.supportedAuthenticationMethods.count
        var buffer = context.channel.allocator.buffer(capacity: capacity)
        buffer.writeClientGreeting(greeting)
        self.state.sendClientGreeting(greeting)
        
        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
        context.fireChannelActive()
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
            guard let action = try self.state.receiveBuffer(&self.buffered) else {
                self.buffered = save
                return
            }
            self.handleAction(action, context: context)
        } catch {
            context.fireErrorCaught(error)
            context.close(mode: .all, promise: nil)
        }
    }
    
    func handleAction(_ action: ClientAction, context: ChannelHandlerContext) {
        
        switch action {
        case .sendRequest:
            let request = ClientRequest(command: .connect, addressType: self.targetAddress, desiredPort: self.targetPort)
            self.state.sendClientRequest(request)
            let capacity = 6 + self.targetAddress.size
            var buffer = context.channel.allocator.buffer(capacity: capacity)
            buffer.writeClientRequest(request)
            context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
        case .proxyEstablished:
            // for some reason we have extra bytes
            // so let's send them down the pipe
            if self.buffered.readableBytes > 0 {
                let data = self.wrapInboundOut(self.buffered)
                context.fireChannelRead(data)
            }
            break
        case.none:
            break
        }
    }
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        guard self.state.proxyEstablished else {
            promise?.fail(ProxyNotEstablished())
            return
        }
        context.write(data, promise: nil)
    }
    
}
