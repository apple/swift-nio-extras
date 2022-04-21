//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2023 Apple Inc. and the SwiftNIO project authors
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
public final class NIORequestResponseWithIDHandler<Request: NIORequestIdentifiable,
                                                   Response: NIORequestIdentifiable>: ChannelDuplexHandler
                                                  where Request.RequestID == Response.RequestID {
    public typealias InboundIn = Response
    public typealias InboundOut = Never
    public typealias OutboundIn = (Request, EventLoopPromise<Response>)
    public typealias OutboundOut = Request

    private enum State {
        case operational
        case inactive
        case error(Error)

        var isOperational: Bool {
            switch self {
            case .operational:
                return true
            case .error, .inactive:
                return false
            }
        }
    }

    private var state: State = .operational
    private var promiseBuffer: [Request.RequestID: EventLoopPromise<Response>]

    /// Create a new `RequestResponseHandler`.
    ///
    /// - parameters:
    ///    - initialBufferCapacity: `RequestResponseHandler` saves the promises for all outstanding responses in a
    ///          buffer. `initialBufferCapacity` is the initial capacity for this buffer. You usually do not need to set
    ///          this parameter unless you intend to pipeline very deeply and don't want the buffer to resize.
    public init(initialBufferCapacity: Int = 4) {
        self.promiseBuffer = [:]
        self.promiseBuffer.reserveCapacity(initialBufferCapacity)
    }

    public func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .error:
            // We failed any outstanding promises when we entered the error state and will fail any
            // new promises in write.
            assert(self.promiseBuffer.count == 0)
        case .inactive:
            assert(self.promiseBuffer.count == 0)
            // This is weird, we shouldn't get this more than once but it's not the end of the world either. But in
            // debug we probably want to crash.
            assertionFailure("Received channelInactive on an already-inactive NIORequestResponseWithIDHandler")
        case .operational:
            let promiseBuffer = self.promiseBuffer
            self.promiseBuffer.removeAll()
            self.state = .inactive
            promiseBuffer.forEach { promise in
                promise.value.fail(NIOExtrasErrors.ClosedBeforeReceivingResponse())
            }
        }
        context.fireChannelInactive()
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard self.state.isOperational else {
            // we're in an error state, ignore further responses
            assert(self.promiseBuffer.count == 0)
            return
        }

        let response = self.unwrapInboundIn(data)
        if let promise = self.promiseBuffer.removeValue(forKey: response.requestID) {
            promise.succeed(response)
        } else {
            context.fireErrorCaught(NIOExtrasErrors.ResponseForInvalidRequest<Response>(requestID: response.requestID))
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard self.state.isOperational else {
            assert(self.promiseBuffer.count == 0)
            return
        }
        self.state = .error(error)
        let promiseBuffer = self.promiseBuffer
        self.promiseBuffer.removeAll()
        context.close(promise: nil)
        promiseBuffer.forEach {
            $0.value.fail(error)
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let (request, responsePromise) = self.unwrapOutboundIn(data)
        switch self.state {
        case .error(let error):
            assert(self.promiseBuffer.count == 0)
            responsePromise.fail(error)
            promise?.fail(error)
        case .inactive:
            assert(self.promiseBuffer.count == 0)
            promise?.fail(ChannelError.ioOnClosedChannel)
            responsePromise.fail(ChannelError.ioOnClosedChannel)
        case .operational:
            self.promiseBuffer[request.requestID] = responsePromise
            context.write(self.wrapOutboundOut(request), promise: promise)
        }
    }
}

extension NIOExtrasErrors {
    public struct ResponseForInvalidRequest<Response: NIORequestIdentifiable>: NIOExtrasError, Equatable {
        public var requestID: Response.RequestID

        public init(requestID: Response.RequestID) {
            self.requestID = requestID
        }
    }
}

