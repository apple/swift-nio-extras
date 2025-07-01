//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2025 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

/// ``RequestResponseHandler`` receives a `Request` alongside an `EventLoopPromise<Response>` from the `Channel`'s
/// outbound side. It will fulfil the promise with the `Response` once it's received from the `Channel`'s inbound
/// side.
///
/// ``RequestResponseHandler`` does support pipelining `Request`s and it will send them pipelined further down the
/// `Channel`. Should ``RequestResponseHandler`` receive an error from the `Channel`, it will fail all promises meant for
/// the outstanding `Response`s and close the `Channel`. All requests enqueued after an error occurred will be immediately
/// failed with the first error the channel received.
///
/// ``RequestResponseHandler`` requires that the `Response`s arrive on `Channel` in the same order as the `Request`s
/// were submitted.
@preconcurrency
public final class RequestResponseHandler<Request, Response: Sendable>: ChannelDuplexHandler {
    /// `Response` is the type this class expects to receive inbound.
    public typealias InboundIn = Response
    /// Don't expect to pass anything on in-bound.
    public typealias InboundOut = Never
    /// Type this class expect to receive in an outbound direction.
    public typealias OutboundIn = (Request, EventLoopPromise<Response>)
    /// Type this class passes out.
    public typealias OutboundOut = Request

    private var state: RequestResponseHandlerState<OrderedResponsePromiseBuffer<EventLoopPromise<Response>>>

    /// Create a new `RequestResponseHandler`.
    ///
    /// - parameters:
    ///    - initialBufferCapacity: `RequestResponseHandler` saves the promises for all outstanding responses in a
    ///          buffer. `initialBufferCapacity` is the initial capacity for this buffer. You usually do not need to set
    ///          this parameter unless you intend to pipeline very deeply and don't want the buffer to resize.
    public init(initialBufferCapacity: Int = 4) {
        self.state = .init(initialBufferCapacity: initialBufferCapacity)
    }

    public func channelInactive(context: ChannelHandlerContext) {
        switch self.state.deactivateChannel() {
        case .failPromisesAndFireInactive(let promisesToFail):
            for promise in promisesToFail {
                promise.fail(NIOExtrasErrors.ClosedBeforeReceivingResponse())
            }
            context.fireChannelInactive()
        case .fireInactive:
            context.fireChannelInactive()
        case .doNothing:
            return
        }
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response = self.unwrapInboundIn(data)
        switch self.state.readResponse(id: ()) {
        case .succeed(let promise):
            promise.succeed(response)
        // Matching promiseNotFound here as it should never be received from an CircularBuffer as the key is Void.
        case .bufferEmpty, .promiseNotFound:
            context.fireErrorCaught(NIOExtrasErrors.ResponsePromiseBufferEmpty())
        case .notOperational:
            return
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        switch self.state.caughtError(error: error) {
        case .failPromisesAndCloseContext(let promisesToFail):
            for promise in promisesToFail {
                promise.fail(error)
            }
            context.close(promise: nil)
        case .notOperational:
            return
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let (request, responsePromise) = self.unwrapOutboundIn(data)
        switch self.state.writeRequest(id: (), responsePromise: responsePromise) {
        case .failPromise(let error):
            responsePromise.fail(error)
            promise?.fail(error)
        case .writeToContext:
            context.write(self.wrapOutboundOut(request), promise: promise)
        }
    }
}

@available(*, unavailable)
extension RequestResponseHandler: Sendable {}

/// ``NIORequestIsolatedResponseHandler`` receives a `Request` alongside an `EventLoopPromise<Response>.Isolated` from the `Channel`'s
/// outbound side. It will fulfil the promise with the `Response` once it's received from the `Channel`'s inbound
/// side.
///
/// ``NIORequestIsolatedResponseHandler`` does support pipelining `Request`s and it will send them pipelined further down the
/// `Channel`. Should ``NIORequestIsolatedResponseHandler`` receive an error from the `Channel`, it will fail all promises meant for
/// the outstanding `Response`s and close the `Channel`. All requests enqueued after an error occurred will be immediately
/// failed with the first error the channel received.
///
/// ``NIORequestIsolatedResponseHandler`` requires that the `Response`s arrive on `Channel` in the same order as the `Request`s
/// were submitted.
public final class NIORequestIsolatedResponseHandler<Request, Response>: ChannelDuplexHandler {
    /// `Response` is the type this class expects to receive inbound.
    public typealias InboundIn = Response
    /// Don't expect to pass anything on in-bound.
    public typealias InboundOut = Never
    /// Type this class expect to receive in an outbound direction.
    public typealias OutboundIn = (Request, EventLoopPromise<Response>.Isolated)
    /// Type this class passes out.
    public typealias OutboundOut = Request

    private var state: RequestResponseHandlerState<OrderedResponsePromiseBuffer<EventLoopPromise<Response>.Isolated>>

    /// Create a new `NIORequestIsolatedResponseHandler`.
    ///
    /// - parameters:
    ///    - initialBufferCapacity: `NIORequestIsolatedResponseHandler` saves the promises for all outstanding responses in a
    ///          buffer. `initialBufferCapacity` is the initial capacity for this buffer. You usually do not need to set
    ///          this parameter unless you intend to pipeline very deeply and don't want the buffer to resize.
    public init(initialBufferCapacity: Int = 4) {
        self.state = .init(initialBufferCapacity: initialBufferCapacity)
    }

    public func channelInactive(context: ChannelHandlerContext) {
        switch self.state.deactivateChannel() {
        case .failPromisesAndFireInactive(let promisesToFail):
            for promise in promisesToFail {
                promise.nonisolated().fail(NIOExtrasErrors.ClosedBeforeReceivingResponse())
            }
            context.fireChannelInactive()
        case .fireInactive:
            context.fireChannelInactive()
        case .doNothing:
            return
        }
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response = self.unwrapInboundIn(data)
        switch self.state.readResponse(id: ()) {
        case .succeed(let promise):
            promise.succeed(response)
        // Matching promiseNotFound here as it should never be received from an CircularBuffer as the key is Void
        case .bufferEmpty, .promiseNotFound:
            context.fireErrorCaught(NIOExtrasErrors.ResponsePromiseBufferEmpty())
        case .notOperational:
            return
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        switch self.state.caughtError(error: error) {
        case .failPromisesAndCloseContext(let promisesToFail):
            for promise in promisesToFail {
                promise.nonisolated().fail(error)
            }
            context.close(promise: nil)
        case .notOperational:
            return
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let (request, responsePromise) = self.unwrapOutboundIn(data)
        switch self.state.writeRequest(id: (), responsePromise: responsePromise) {
        case .failPromise(let error):
            responsePromise.nonisolated().fail(error)
            promise?.fail(error)
        case .writeToContext:
            context.write(self.wrapOutboundOut(request), promise: promise)
        }
    }
}

@available(*, unavailable)
extension NIORequestIsolatedResponseHandler: Sendable {}
