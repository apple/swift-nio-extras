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

    private var state: RequestResponseHandlerState<ResponseCircularBuffer<Response>>

    /// Create a new `RequestResponseHandler`.
    ///
    /// - parameters:
    ///    - initialBufferCapacity: `RequestResponseHandler` saves the promises for all outstanding responses in a
    ///          buffer. `initialBufferCapacity` is the initial capacity for this buffer. You usually do not need to set
    ///          this parameter unless you intend to pipeline very deeply and don't want the buffer to resize.
    public init(initialBufferCapacity: Int = 4) {
        state = .init(initialBufferCapacity: initialBufferCapacity)
    }

    public func channelInactive(context: ChannelHandlerContext) {
        switch state.deactivateChannel() {
        case .fireInactive: context.fireChannelInactive()
        case .`return`: return
        }
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response = self.unwrapInboundIn(data)
        switch self.state.readPromise(id: ()) {
        case .succeed(let promiseEnum):
            switch promiseEnum {
            case .nonisolated(let promise):
                if promise.futureResult.eventLoop === context.eventLoop {
                    promise.succeed(response)
                } else {
                    promise.futureResult.eventLoop.execute {
                        promise.succeed(response)
                    }
                }
            case .isolated(_):
                // The type checker will not allow the responses to be isolated.
                fatalError("Unreachable: RequestResponseHandler received isolated promise")
            }
        // Matching promiseNotFound here as it should never be received from an CircularBuffer as the key is Void.
        case .bufferEmpty, .promiseNotFound:
            context.fireErrorCaught(NIOExtrasErrors.ResponseOnEmptyBuffer())
        case .return: return
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        switch self.state.errorCaught(error: error) {
        case .closeContext: context.close(promise: nil)
        case .return: return
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let (request, responsePromise) = self.unwrapOutboundIn(data)
        switch self.state.writePromise(id: (), responsePromise: .nonisolated(responsePromise)) {
        case .failWith(let error):
            responsePromise.fail(error)
            promise?.fail(error)
        case .writeContext: context.write(self.wrapOutboundOut(request), promise: promise)
        }
    }
}

@available(*, unavailable)
extension RequestResponseHandler: Sendable {}

/// ``NIORequestIsolatedResponseHandler`` receives a `Request` alongside an `EventLoopPromise<Response>` from the `Channel`'s
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

    private var state: RequestResponseHandlerState<ResponseCircularBuffer<Response>>

    /// Create a new `NIORequestIsolatedResponseHandler`.
    ///
    /// - parameters:
    ///    - initialBufferCapacity: `NIORequestIsolatedResponseHandler` saves the promises for all outstanding responses in a
    ///          buffer. `initialBufferCapacity` is the initial capacity for this buffer. You usually do not need to set
    ///          this parameter unless you intend to pipeline very deeply and don't want the buffer to resize.
    public init(initialBufferCapacity: Int = 4) {
        state = .init(initialBufferCapacity: initialBufferCapacity)
    }

    public func channelInactive(context: ChannelHandlerContext) {
        switch state.deactivateChannel() {
        case .fireInactive: context.fireChannelInactive()
        case .`return`: return
        }
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response = self.unwrapInboundIn(data)
        switch self.state.readPromise(id: ()) {
        case .succeed(let promiseEnum):
            switch promiseEnum {
            case .isolated(let promise):
                if promise.futureResult.nonisolated().eventLoop === context.eventLoop {
                    promise.succeed(response)
                } else {
                    promise.nonisolated().fail(NIOExtrasErrors.IsolatedPromiseUsedFromDifferentEventLoop())
                }
            case .nonisolated(_):
                // The type checker will not allow the responses to be nonisolated.
                fatalError("Unreachable: NIORequestIsolatedResponseHandler received nonisolated promise")
            }
        // Matching promiseNotFound here as it should never be received from an CircularBuffer as the key is Void
        case .bufferEmpty, .promiseNotFound:
            context.fireErrorCaught(NIOExtrasErrors.ResponseOnEmptyBuffer())
        case .return: return
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        switch self.state.errorCaught(error: error) {
        case .closeContext: context.close(promise: nil)
        case .return: return
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let (request, responsePromise) = self.unwrapOutboundIn(data)
        switch self.state.writePromise(id: (), responsePromise: .isolated(responsePromise)) {
        case .failWith(let error):
            responsePromise.nonisolated().fail(error)
            promise?.fail(error)
        case .writeContext: context.write(self.wrapOutboundOut(request), promise: promise)
        }
    }
}

@available(*, unavailable)
extension NIORequestIsolatedResponseHandler: Sendable {}
