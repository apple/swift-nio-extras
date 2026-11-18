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
/// The handler works with HTTP/1.1 and HTTP/2 pipelines alike (both share the
/// `HTTPRequestPart` abstraction). On HTTP/2 the channel close is translated
/// into a GOAWAY by the codec. For a stream-level reset (`RST_STREAM`) instead
/// of a connection close, configure ``NIOHTTPBodyLimitOverflowAction/fail`` and
/// emit the reset from your application's `errorCaught` handler.
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

    /// Outcome of checking one inbound request part against the size limit.
    private enum FrameDecision {
        /// The part is within the limit: forward it to the application.
        case forward
        /// The limit is exceeded by this part: reject the request and stop
        /// forwarding the remainder of it.
        case overflow(received: Int)
        /// The request was already rejected: discard the part silently.
        case discard
    }

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
            let headDecision = self.state.withLockedValue { state -> FrameDecision in
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
                    return .overflow(received: declaredLength)
                }
                return .forward
            }

            switch headDecision {
            case .forward:
                context.fireChannelRead(data)
            case .overflow(let received):
                self.onOverflow(context: context, received: received)
            case .discard:
                break
            }

        case .body(let buffer):
            // Streaming layer: count bytes as they arrive.
            let bodyDecision = self.state.withLockedValue { state -> FrameDecision in
                if state.didViolate {
                    // Already rejected: stop forwarding this request's body and
                    // discard remaining frames (no buffering, no further checks).
                    return .discard
                }

                // Buffer the counter against wraparound: on absurdly large streams
                // treat the overflow as a limit violation instead of wrapping.
                let (newTotal, overflowed) = state.receivedBodyBytes
                    .addingReportingOverflow(buffer.readableBytes)
                if overflowed {
                    state.receivedBodyBytes = .max
                    state.didViolate = true
                    return .overflow(received: .max)
                }

                state.receivedBodyBytes = newTotal
                if newTotal > self.limit {
                    state.didViolate = true
                    return .overflow(received: newTotal)
                }
                return .forward
            }

            switch bodyDecision {
            case .forward:
                context.fireChannelRead(data)
            case .overflow(let received):
                self.onOverflow(context: context, received: received)
            case .discard:
                break
            }

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
            // No connection-specific headers: they are valid in HTTP/1.1 but not
            // in HTTP/2. Closing the channel is the protocol-agnostic signal; on
            // HTTP/2 the codec translates it into a GOAWAY.
            let responseHead = HTTPResponse(
                status: status,
                headerFields: HTTPFields(dictionaryLiteral: (.contentLength, "0"))
            )

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
