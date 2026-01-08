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

import NIOCore

/// Connects to a SOCKS server to establish a proxied connection
/// to a host. This handler should be inserted at the beginning of a
/// channel's pipeline. Note that SOCKS only supports fully-qualified
/// domain names and IPv4 or IPv6 sockets, and not UNIX sockets.
public final class SOCKSClientHandler: ChannelDuplexHandler {
    /// Accepts `ByteBuffer` as input where receiving.
    public typealias InboundIn = ByteBuffer
    /// Sends `ByteBuffer` to the next pipeline stage when receiving.
    public typealias InboundOut = ByteBuffer
    /// Accepts `ByteBuffer` as the type to send.
    public typealias OutboundIn = ByteBuffer
    /// Sends `ByteBuffer` to the next outbound stage.
    public typealias OutboundOut = ByteBuffer

    private let targetAddress: SOCKSAddress

    private var state: ClientStateMachine
    private var removalToken: ChannelHandlerContext.RemovalToken?
    private var inboundBuffer: ByteBuffer?

    private var bufferedWrites: MarkedCircularBuffer<(NIOAny, EventLoopPromise<Void>?)> = .init(initialCapacity: 8)

    /// Creates a new ``SOCKSClientHandler`` that connects to a server
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
        context.fireChannelActive()
    }

    /// Add handler to pipeline and start handshake.
    /// - Parameter context: Calling context.
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
            context.close(promise: nil)
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        if self.state.proxyEstablished && self.bufferedWrites.count == 0 {
            context.write(data, promise: promise)
        } else {
            self.bufferedWrites.append((data, promise))
        }
    }

    private func writeBufferedData(context: ChannelHandlerContext) {
        guard self.state.proxyEstablished else {
            return
        }
        while self.bufferedWrites.hasMark {
            let (data, promise) = self.bufferedWrites.removeFirst()
            context.write(data, promise: promise)
        }
        context.flush()  // safe to flush otherwise we wouldn't have the mark

        while !self.bufferedWrites.isEmpty {
            let (data, promise) = self.bufferedWrites.removeFirst()
            context.write(data, promise: promise)
        }
    }

    public func flush(context: ChannelHandlerContext) {
        self.bufferedWrites.mark()
        self.writeBufferedData(context: context)
    }
}

@available(*, unavailable)
extension SOCKSClientHandler: Sendable {}

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
            break  // do nothing, we've already buffered the data
        case .sendGreeting:
            try self.handleActionSendClientGreeting(context: context)
        case .sendRequest:
            try self.handleActionSendRequest(context: context)
        case .proxyEstablished:
            self.handleProxyEstablished(context: context)
        }
    }

    private func handleActionSendClientGreeting(context: ChannelHandlerContext) throws {
        let greeting = ClientGreeting(methods: [.noneRequired])  // no authentication currently supported
        let capacity = 3  // [version, #methods, methods...]
        var buffer = context.channel.allocator.buffer(capacity: capacity)
        buffer.writeClientGreeting(greeting)
        try self.state.sendClientGreeting(greeting)
        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
    }

    private func handleProxyEstablished(context: ChannelHandlerContext) {
        context.fireUserInboundEventTriggered(SOCKSProxyEstablishedEvent())

        self.emptyInboundAndOutboundBuffer(context: context)

        if let removalToken = self.removalToken {
            context.leavePipeline(removalToken: removalToken)
        }
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

    private func emptyInboundAndOutboundBuffer(context: ChannelHandlerContext) {
        if let inboundBuffer = self.inboundBuffer, inboundBuffer.readableBytes > 0 {
            // after the SOCKS handshake message we already received further bytes.
            // so let's send them down the pipe
            self.inboundBuffer = nil
            context.fireChannelRead(self.wrapInboundOut(inboundBuffer))
        }

        // If we have any buffered writes, we must send them before we are removed from the pipeline
        self.writeBufferedData(context: context)
    }
}

extension SOCKSClientHandler: RemovableChannelHandler {

    public func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
        guard self.state.proxyEstablished else {
            self.removalToken = removalToken
            return
        }

        // We must clear the buffers here before we are removed, since the
        // handler removal may be triggered as a side effect of the
        // `SOCKSProxyEstablishedEvent`. In this case we may end up here,
        // before the buffer empty method in `handleProxyEstablished` is
        // invoked.
        self.emptyInboundAndOutboundBuffer(context: context)
        context.leavePipeline(removalToken: removalToken)
    }

}

/// A `Channel` user event that is sent when a SOCKS connection has been established
///
/// After this event has been received it is save to remove the `SOCKSClientHandler` from the channel pipeline.
public struct SOCKSProxyEstablishedEvent: Sendable {
    public init() {
    }
}
