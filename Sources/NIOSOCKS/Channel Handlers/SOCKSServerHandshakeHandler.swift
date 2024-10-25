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

/// Add this handshake handler to the front of your channel, closest to the network.
/// The handler will receive bytes from the network and run them through a state machine
/// and parser to enforce SOCKSv5 protocol correctness. Inbound bytes will by parsed into
/// ``ClientMessage`` for downstream consumption. Send ``ServerMessage`` to this
/// handler.
public final class SOCKSServerHandshakeHandler: ChannelDuplexHandler, RemovableChannelHandler {
    /// Accepts `ByteBuffer` when receiving data.
    public typealias InboundIn = ByteBuffer
    /// Passes `ClientMessage` to the next stage of the pipeline when receiving data.
    public typealias InboundOut = ClientMessage
    /// Accepts `ServerMessage` when sending data.
    public typealias OutboundIn = ServerMessage
    /// Passes `ByteBuffer` to the next pipeline stage when sending data.
    public typealias OutboundOut = ByteBuffer

    var inboundBuffer: ByteBuffer?
    var stateMachine: ServerStateMachine

    public init() {
        self.stateMachine = ServerStateMachine()
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {

        var message = self.unwrapInboundIn(data)
        self.inboundBuffer.setOrWriteBuffer(&message)

        if self.stateMachine.proxyEstablished {
            return
        }

        do {
            // safe to bang inbound buffer, it's always written above
            guard let message = try self.stateMachine.receiveBuffer(&self.inboundBuffer!) else {
                return  // do nothing, we've buffered the data
            }
            context.fireChannelRead(self.wrapInboundOut(message))
        } catch {
            context.fireErrorCaught(error)
        }
    }

    /// Add hander to pipeline and enter state ready for connection establishment.
    /// - Parameter context: Calling context
    public func handlerAdded(context: ChannelHandlerContext) {
        do {
            try self.stateMachine.connectionEstablished()
        } catch {
            context.fireErrorCaught(error)
        }
    }

    /// Remove handler from channel pipeline.  Causes any inbound buffer to be surfaced.
    /// - Parameter context:  Calling context.
    public func handlerRemoved(context: ChannelHandlerContext) {
        guard let buffer = self.inboundBuffer else {
            return
        }
        context.fireChannelRead(.init(buffer))
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        do {
            let message = self.unwrapOutboundIn(data)
            let outboundBuffer: ByteBuffer
            switch message {
            case .selectedAuthenticationMethod(let method):
                outboundBuffer = try self.handleWriteSelectedAuthenticationMethod(method, context: context)
            case .response(let response):
                outboundBuffer = try self.handleWriteResponse(response, context: context)
            case .authenticationData(let data, let complete):
                outboundBuffer = try self.handleWriteAuthenticationData(data, complete: complete, context: context)
            }
            context.write(self.wrapOutboundOut(outboundBuffer), promise: promise)

        } catch {
            context.fireErrorCaught(error)
            promise?.fail(error)
        }
    }

    private func handleWriteSelectedAuthenticationMethod(
        _ method: SelectedAuthenticationMethod,
        context: ChannelHandlerContext
    ) throws -> ByteBuffer {
        try stateMachine.sendAuthenticationMethod(method)
        var buffer = context.channel.allocator.buffer(capacity: 16)
        buffer.writeMethodSelection(method)
        return buffer
    }

    private func handleWriteResponse(
        _ response: SOCKSResponse,
        context: ChannelHandlerContext
    ) throws -> ByteBuffer {
        try stateMachine.sendServerResponse(response)
        if case .succeeded = response.reply {
            context.fireUserInboundEventTriggered(SOCKSProxyEstablishedEvent())
        }
        var buffer = context.channel.allocator.buffer(capacity: 16)
        buffer.writeServerResponse(response)
        return buffer
    }

    private func handleWriteAuthenticationData(
        _ data: ByteBuffer,
        complete: Bool,
        context: ChannelHandlerContext
    ) throws -> ByteBuffer {
        try self.stateMachine.sendAuthenticationData(data, complete: complete)
        return data
    }

}

@available(*, unavailable)
extension SOCKSServerHandshakeHandler: Sendable {}
