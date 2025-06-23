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

/// `NIORequestResponseWithIDHandler` receives a `Request` alongside an `EventLoopPromise<Response>` from the
/// `Channel`'s outbound side. It will fulfill the promise with the `Response` once it's received from the `Channel`'s
/// inbound side. Requests and responses can arrive out-of-order and are matched by the virtue of being
/// `NIORequestIdentifiable`.
///
/// `NIORequestResponseWithIDHandler` does support pipelining `Request`s and it will send them pipelined further down the
/// `Channel`. Should `RequestResponseHandler` receive an error from the `Channel`, it will fail all promises meant for
/// the outstanding `Reponse`s and close the `Channel`. All requests enqueued after an error occured will be immediately
/// failed with the first error the channel received.
///
/// `NIORequestResponseWithIDHandler` does _not_ require that the `Response`s arrive on `Channel` in the same order as
/// the `Request`s were submitted. They are matched by their `requestID` property (from `NIORequestIdentifiable`).
public final class NIORequestResponseWithIDHandler<
    Request: NIORequestIdentifiable,
    Response: NIORequestIdentifiable,
>: ChannelDuplexHandler
where Request.RequestID == Response.RequestID, Response: Sendable {
    public typealias InboundIn = Response
    public typealias InboundOut = Never
    public typealias OutboundIn = (Request, EventLoopPromise<Response>)
    public typealias OutboundOut = Request

    private var state: RequestResponseHandlerState<ResponseDictionaryBuffer<Response>>

    /// Create a new `NIORequestResponseWithIDHandler`.
    ///
    /// - parameters:
    ///    - initialBufferCapacity: `NIORequestResponseWithIDHandler` saves the promises for all outstanding responses in a
    ///          buffer. `initialBufferCapacity` is the initial capacity for this buffer. You usually do not need to set
    ///          this parameter unless you intend to pipeline very deeply and don't want the buffer to resize.
    public init(initialBufferCapacity: Int = 4) {
        state = .init(initialBufferCapacity: 4)
    }

    public func channelInactive(context: ChannelHandlerContext) {
        switch state.deactivateChannel() {
        case .fireInactive: context.fireChannelInactive()
        case .`return`: return
        }
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response = self.unwrapInboundIn(data)
        switch self.state.readPromise(id: response.requestID) {
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
                fatalError("Unreachable: NIORequestResponseWithIDHandler received isolated promise")
            }
        case .error:
            context.fireErrorCaught(NIOExtrasErrors.ResponseForInvalidRequest<Response>(requestID: response.requestID))
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
        switch self.state.writePromise(id: request.requestID, responsePromise: .nonisolated(responsePromise)) {
        case .failWith(let error):
            responsePromise.fail(error)
            promise?.fail(error)
        case .writeContext: context.write(self.wrapOutboundOut(request), promise: promise)
        }
    }
}

@available(*, unavailable)
extension NIORequestResponseWithIDHandler: Sendable {}

/// `NIORequestIsolatedResponseWithIDHandler` receives a `Request` alongside an `EventLoopPromise<Response>.Isolated` from the
/// `Channel`'s outbound side. It will fulfill the promise with the `Response` once it's received from the `Channel`'s
/// inbound side. Requests and responses can arrive out-of-order and are matched by the virtue of being
/// `NIORequestIdentifiable`.
///
/// `NIORequestIsolatedResponseWithIDHandler` does support pipelining `Request`s and it will send them pipelined further down the
/// `Channel`. Should `RequestResponseHandler` receive an error from the `Channel`, it will fail all promises meant for
/// the outstanding `Reponse`s and close the `Channel`. All requests enqueued after an error occured will be immediately
/// failed with the first error the channel received.
///
/// `NIORequestIsolatedResponseWithIDHandler` does _not_ require that the `Response`s arrive on `Channel` in the same order as
/// the `Request`s were submitted. They are matched by their `requestID` property (from `NIORequestIdentifiable`).
///
public final class NIORequestIsolatedResponseWithIDHandler<
    Request: NIORequestIdentifiable,
    Response: NIORequestIdentifiable,
>: ChannelDuplexHandler
where Request.RequestID == Response.RequestID {
    public typealias InboundIn = Response
    public typealias InboundOut = Never
    public typealias OutboundIn = (Request, EventLoopPromise<Response>.Isolated)
    public typealias OutboundOut = Request

    private var state: RequestResponseHandlerState<ResponseDictionaryBuffer<Response>>

    /// Create a new `NIORequestIsolatedResponseWithIDHandler`.
    ///
    /// - parameters:
    ///    - initialBufferCapacity: `NIORequestIsolatedResponseWithIDHandler` saves the promises for all outstanding responses in a
    ///          buffer. `initialBufferCapacity` is the initial capacity for this buffer. You usually do not need to set
    ///          this parameter unless you intend to pipeline very deeply and don't want the buffer to resize.
    public init(initialBufferCapacity: Int = 4) {
        state = .init(initialBufferCapacity: 4)
    }

    public func channelInactive(context: ChannelHandlerContext) {
        switch state.deactivateChannel() {
        case .fireInactive: context.fireChannelInactive()
        case .`return`: return
        }
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response = self.unwrapInboundIn(data)
        switch self.state.readPromise(id: response.requestID) {
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
                fatalError("Unreachable: NIORequestIsolatedResponseWithIDHandler received nonisolated promise")
            }
        case .error:
            context.fireErrorCaught(NIOExtrasErrors.ResponseForInvalidRequest<Response>(requestID: response.requestID))
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
        switch self.state.writePromise(id: request.requestID, responsePromise: .isolated(responsePromise)) {
        case .failWith(let error):
            responsePromise.nonisolated().fail(error)
            promise?.fail(error)
        case .writeContext: context.write(self.wrapOutboundOut(request), promise: promise)
        }
    }
}

@available(*, unavailable)
extension NIORequestIsolatedResponseWithIDHandler: Sendable {}

extension NIOExtrasErrors {
    public struct ResponseForInvalidRequest<Response: NIORequestIdentifiable>: NIOExtrasError, Equatable {
        public var requestID: Response.RequestID

        public init(requestID: Response.RequestID) {
            self.requestID = requestID
        }
    }
}
