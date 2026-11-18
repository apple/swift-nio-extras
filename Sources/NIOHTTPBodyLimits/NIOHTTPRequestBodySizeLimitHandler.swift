//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2026 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import HTTPTypes
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTPTypes

/// A `ChannelInboundHandler` that protects an HTTP server from oversized
/// incoming request bodies.
///
/// The handler counts the request body *while it is streaming*: it never
/// aggregates the individual `HTTPRequestPart.body` frames into a single
/// buffer, so an oversized body costs no additional memory. Two protection
/// layers work together:
///
/// 1. **Header layer:** when the request head arrives, the declared
///    `Content-Length` is checked. If it exceeds the limit, the request is
///    rejected *before the client has (necessarily) sent any body bytes*
///    (ideal for `Expect: 100-continue` clients).
/// 2. **Streaming layer:** for chunked bodies, or when the declared length
///    turns out to be smaller than what actually arrives, every `.body` frame
///    is counted. The moment the running total exceeds the limit, further
///    body bytes are discarded instead of forwarded.
///
/// On violation the connection is always closed. What the client sees first is
/// configurable via ``NIOHTTPBodyLimitOverflowAction``: by default a 413 Content
/// Too Large response is written out, so the client receives an explicit error
/// instead of a silent connection reset.
///
/// Example usage with an HTTP/1.1 server built on `NIOHTTPTypes`:
///
///     let handler = NIOHTTPRequestBodySizeLimitHandler(limit: 1024 * 1024)
///     channel.pipeline.addHandler(handler)
///
/// For HTTP/2 servers, prefer ``NIOHTTPBodyLimitOverflowAction/fail`` and emit
/// `RST_STREAM` from the application's error handler, since the `Connection:
/// close` header sent in response mode is not a valid HTTP/2 construct.
public final class NIOHTTPRequestBodySizeLimitHandler: ChannelInboundHandler {
    public typealias InboundIn = HTTPRequestPart
    public typealias InboundOut = HTTPRequestPart
    public typealias OutboundOut = HTTPResponsePart

    private let limit: Int
    private let overflowAction: NIOHTTPBodyLimitOverflowAction

    /// Per-request state. Confined to a single event loop thread in practice;
    /// kept behind a lock so the handler is a valid `Sendable` type.
    private struct PerRequestState {
        var receivedBodyBytes = 0
        var didViolate = false

        // Tracked so violations discovered mid-body can produce a meaningful error.
        var lastMethod: HTTPRequest.Method = .get
        var lastPath: String = ""
    }

    private let state = NIOLockedValueBox(PerRequestState())

    /// Creates a new request body size limit handler.
    ///
    /// - Parameters:
    ///   - limit: The maximum number of request body bytes, per request. A
    ///      limit of `0` rejects any request that carries a body.
    ///   - overflowAction: The action to take when the limit is exceeded.
    ///      Defaults to responding with 413 Content Too Large and closing.
    public init(limit: Int, overflowAction: NIOHTTPBodyLimitOverflowAction = .respond(status: .contentTooLarge)) {
        precondition(limit >= 0, "limit must be zero or positive")
        self.limit = limit
        self.overflowAction = overflowAction
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = self.unwrapInboundIn(data)

        switch part {
        case .head(let request):
            // A new request begins (this handler also supports HTTP/1.1 pipelining):
            // reset the per-request accounting and arm the header-layer check.
            let headerOverflow = self.state.withLockedValue { state -> Int? in
                state.receivedBodyBytes = 0
                state.didViolate = false
                state.lastMethod = request.method
                state.lastPath = request.path ?? ""

                // Header layer: reject immediately when the declared length alone
                // exceeds the limit. A missing or malformed header falls through to
                // the streaming layer below.
                if let declaredLength = Int(request.headerFields[.contentLength] ?? ""),
                    declaredLength > self.limit
                {
                    state.didViolate = true
                    return declaredLength
                }
                return nil
            }

            if let headerOverflow {
                self.onOverflow(context: context, received: headerOverflow)
                return
            }

            context.fireChannelRead(data)

        case .body(let buffer):
            // Streaming layer: count bytes as they arrive.
            let overflow = self.state.withLockedValue { state -> Int? in
                if state.didViolate {
                    // Already rejected: stop forwarding this request's body and
                    // discard remaining frames (no buffering, no further checks).
                    return nil
                }

                state.receivedBodyBytes += buffer.readableBytes
                if state.receivedBodyBytes > self.limit {
                    state.didViolate = true
                    return state.receivedBodyBytes
                }
                return nil
            }

            if let overflow {
                self.onOverflow(context: context, received: overflow)
                return
            }

            context.fireChannelRead(data)

        case .end:
            // Nothing is forwarded for a rejected request: send only if acceptable.
            let violated = self.state.withLockedValue { $0.didViolate }
            if !violated {
                context.fireChannelRead(data)
            }
        }
    }

    private func onOverflow(context: ChannelHandlerContext, received: Int) {
        let (method, path) = self.state.withLockedValue { ($0.lastMethod, $0.lastPath) }

        switch self.overflowAction {
        case .respond(let status):
            var headerFields = HTTPFields()
            headerFields[.contentLength] = "0"
            headerFields[.connection] = "close"
            let responseHead = HTTPResponse(status: status, headerFields: headerFields)

            context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            context.close(promise: nil)

        case .fail:
            context.fireErrorCaught(
                NIOHTTPBodyLimitOverflowError(
                    method: method,
                    path: path,
                    limit: self.limit,
                    received: received
                )
            )
            context.close(promise: nil)
        }
    }
}

extension NIOHTTPRequestBodySizeLimitHandler: Sendable {}
