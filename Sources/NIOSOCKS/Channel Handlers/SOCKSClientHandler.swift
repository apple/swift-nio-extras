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

/// Connects to a SOCKS server to establish a proxied connection
/// to a host. This handler should be inserted at the beginning of a
/// channel's pipeline.
public class SOCKSClientHandler: ChannelDuplexHandler {
    
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    
    private let targetAddress: AddressType
    
    private var state: ClientStateMachine
    private var buffered: ByteBuffer
    
    private var bufferedWrites: [(NIOAny, EventLoopPromise<Void>?)] = []
    
    public init(targetAddress: AddressType) {
        
        switch targetAddress {
        case .address(.unixDomainSocket):
            preconditionFailure("UNIX domain sockets are not supported.")
        case .domain, .address(.v4), .address(.v6):
            break
        }
        
        self.state = ClientStateMachine()
        self.buffered = ByteBuffer()
        self.targetAddress = targetAddress
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        self.beginHandshake(context: context)
    }
    
    public func handlerAdded(context: ChannelHandlerContext) {
        self.beginHandshake(context: context)
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        
        // if we've established the connection then forward on the data
        guard !self.state.proxyEstablished else {
            context.fireChannelRead(data)
            return
        }
        
        var buffer = self.unwrapInboundIn(data)
        self.buffered.writeBuffer(&buffer)
        do {
            let action = try self.state.receiveBuffer(&self.buffered)
            try self.handleAction(action, context: context)
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
        self.writeBufferedData(context: context)
        context.write(data, promise: nil)
    }
    
    func writeBufferedData(context: ChannelHandlerContext) {
        while self.bufferedWrites.count > 0 {
            let (data, promise) = self.bufferedWrites.removeFirst()
            context.write(data, promise: promise)
        }
    }
    
}

extension SOCKSClientHandler {
    
    func beginHandshake(context: ChannelHandlerContext) {
        do {
            guard self.state.shouldBeginHandshake else {
                return
            }
            try self.handleAction(self.state.connectionEstablished(), context: context)
        } catch {
            context.fireErrorCaught(error)
            context.close(promise: nil)
        }
    }
    
    func handleAction(_ action: ClientAction, context: ChannelHandlerContext) throws {
        switch action {
        case .waitForMoreData:
            break // do nothing, we've already buffered the data
        case .sendGreeting:
            try self.handleActionSendClientGreeting(context: context)
        case .sendRequest:
            try self.handleActionSendRequest(context: context)
        case .proxyEstablished:
            self.handleActionProxyEstablished(context: context)
        case .sendData(let data):
            context.writeAndFlush(self.wrapOutboundOut(data), promise: nil)
        }
    }
    
    func handleActionSendClientGreeting(context: ChannelHandlerContext) throws {
        let greeting = ClientGreeting(methods: [.noneRequired]) // no authentication currently supported
        let capacity = 1 + 1 + 1 // [version, #methods, methods...]
        var buffer = context.channel.allocator.buffer(capacity: capacity)
        buffer.writeClientGreeting(greeting)
        try self.state.sendClientGreeting(greeting)
        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
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
        self.writeBufferedData(context: context)
    }
    
    func handleActionSendRequest(context: ChannelHandlerContext) throws {
        let request = ClientRequest(command: .connect, addressType: self.targetAddress)
        try self.state.sendClientRequest(request)
        
        // the client request is always 6 bytes + the address info
        // [protocol_version, command, reserved, address type, <address>, port (2bytes)]
        let capacity = 6 + self.targetAddress.size
        var buffer = context.channel.allocator.buffer(capacity: capacity)
        buffer.writeClientRequest(request)
        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
    }
    
}
