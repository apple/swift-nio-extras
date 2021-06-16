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
/// channel's pipeline. Note that SOCKS only supports fully-qualified
/// domain names and IPv4 or IPv6 sockets, and not UNIX sockets.
public final class SOCKSClientHandler: ChannelDuplexHandler {
    
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    
    private let targetAddress: SOCKSAddress
    
    private var state: ClientStateMachine
    private var inboundBuffer: ByteBuffer?
    
    private var bufferedWrites: MarkedCircularBuffer<(NIOAny, EventLoopPromise<Void>?)> = .init(initialCapacity: 8)
    
    /// Creates a new `SOCKSClientHandler` that connects to a server
    /// and instructs the server to connect to `targetAddress`.
    /// - parameter targetAddress: The desired end point - note that only IPv4, IPv6, and FQDNs are supported.
    public init(targetAddress: SOCKSAddress) {
        
        switch targetAddress {
        case .address(.unixDomainSocket):
            preconditionFailure("UNIX domain sockets are not supported.")
        case .domain, .address(.v4), .address(.v6):
            break
        }
        
        self.state = ClientStateMachine()
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
        if self.state.proxyEstablished {
            context.fireChannelRead(data)
            return
        }
        
        var inboundBuffer = self.unwrapInboundIn(data)
        
        self.inboundBuffer.setOrWriteBuffer(&inboundBuffer)
        do {
            // Safe to bang, `setOrWrite` above means there will
            // always be a value.
            let action = try self.state.receiveBuffer(&self.inboundBuffer!)
            try self.handleAction(action, context: context)
        } catch {
            context.fireErrorCaught(error)
            context.close(mode: .all, promise: nil)
        }
    }
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = self.unwrapOutboundIn(data)
        self.bufferedWrites.append((data, promise))
    }
    
    private func writeBufferedData(context: ChannelHandlerContext) {
        guard self.state.proxyEstablished else {
            return
        }
        while self.bufferedWrites.hasMark {
            let (data, promise) = self.bufferedWrites.removeFirst()
            context.write(data, promise: promise)
        }
        context.flush() // safe to flush otherwise we wouldn't have the mark
    }
    
    public func flush(context: ChannelHandlerContext) {
        self.bufferedWrites.mark()
        self.writeBufferedData(context: context)
    }
}

extension SOCKSClientHandler {
    
    private func beginHandshake(context: ChannelHandlerContext) {
        guard context.channel.isActive, self.state.shouldBeginHandshake else {
            return
        }
        do {
            try self.handleAction(self.state.connectionEstablished(), context: context)
        } catch {
            context.fireErrorCaught(error)
            context.close(promise: nil)
        }
    }
    
    private func handleAction(_ action: ClientAction, context: ChannelHandlerContext) throws {
        switch action {
        case .waitForMoreData:
            break // do nothing, we've already buffered the data
        case .sendGreeting:
            try self.handleActionSendClientGreeting(context: context)
        case .sendRequest:
            try self.handleActionSendRequest(context: context)
        case .proxyEstablished:
            self.handleProxyEstablished(context: context)
        }
    }
    
    private func handleActionSendClientGreeting(context: ChannelHandlerContext) throws {
        let greeting = ClientGreeting(methods: [.noneRequired]) // no authentication currently supported
        let capacity = 3 // [version, #methods, methods...]
        var buffer = context.channel.allocator.buffer(capacity: capacity)
        buffer.writeClientGreeting(greeting)
        try self.state.sendClientGreeting(greeting)
        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
    }
    
    private func handleProxyEstablished(context: ChannelHandlerContext) {
        // for some reason we have extra bytes
        // so let's send them down the pipe
        // (Safe to bang, self.buffered will always exist at this point)
        if self.inboundBuffer!.readableBytes > 0 {
            let data = self.wrapInboundOut(self.inboundBuffer!)
            context.fireChannelRead(data)
        }
        
        // If we have any buffered writes then now
        // we can send them.
        self.writeBufferedData(context: context)
    }
    
    private func handleActionSendRequest(context: ChannelHandlerContext) throws {
        let request = SOCKSRequest(command: .connect, addressType: self.targetAddress)
        try self.state.sendClientRequest(request)
        
        // the client request is always 6 bytes + the address info
        // [protocol_version, command, reserved, address type, <address>, port (2bytes)]
        let capacity = 6 + self.targetAddress.size
        var buffer = context.channel.allocator.buffer(capacity: capacity)
        buffer.writeClientRequest(request)
        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
    }
    
}
