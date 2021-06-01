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

public struct ProxyNotEstablished: Error {
    
}

public class SocksClientHandler: ChannelDuplexHandler, RemovableChannelHandler {
    
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    
    public let supportedAuthenticationMethods: [AuthenticationMethod]
    
    private var state: ClientStateMachine
    private var buffered: ByteBuffer
    
    public init(supportedAuthenticationMethods: [AuthenticationMethod]) {
        precondition(supportedAuthenticationMethods.count <= 255)
        self.supportedAuthenticationMethods = supportedAuthenticationMethods
        self.state = ClientStateMachine()
        self.buffered = ByteBuffer()
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        context.fireChannelInactive()
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        let greeting = ClientGreeting(
            methods: self.supportedAuthenticationMethods
        )
        var buffer = ByteBuffer()
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
        guard let action = self.state.receiveBuffer(&self.buffered) else {
            self.buffered = save
            return
        }
        
        switch action {
        case .sendRequest:
            let request = ClientRequest(version: 5, command: .connect, addressType: .ipv4([192, 168, 1, 2]), desiredPort: 8581)
            self.state.sendClientRequest(request)
            var buffer = ByteBuffer()
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
