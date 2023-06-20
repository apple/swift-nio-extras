//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOHTTP1
import NIOHTTPTypes

/// A simple channel handler that translates shared HTTP types into HTTP/1 messages,
/// and vice versa, for use on the client side.
///
/// This is intended for compatibility purposes where a channel handler working with
/// HTTP/1 messages needs to work on top of the new version-independent HTTP types
/// abstraction.
public final class HTTPToHTTP1ClientCodec: ChannelInboundHandler, ChannelOutboundHandler {
    public typealias InboundIn = HTTPTypeClientResponsePart
    public typealias InboundOut = HTTPClientResponsePart

    public typealias OutboundIn = HTTPClientRequestPart
    public typealias OutboundOut = HTTPTypeClientRequestPart

    private let secure: Bool
    private let splitCookie: Bool

    /// Initializes a `HTTPToHTTP1ClientCodec`.
    /// - Parameters:
    ///   - secure: Whether "https" or "http" is used.
    ///   - splitCookie: Whether the cookies sent by the client should be split
    ///                  into multiple header fields. Defaults to true.
    public init(secure: Bool, splitCookie: Bool = true) {
        self.secure = secure
        self.splitCookie = splitCookie
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            context.fireChannelRead(wrapInboundOut(.head(HTTPResponseHead(head))))
        case .body(let body):
            context.fireChannelRead(wrapInboundOut(.body(body)))
        case .end(let trailers):
            context.fireChannelRead(wrapInboundOut(.end(trailers.map(HTTPHeaders.init))))
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        switch unwrapOutboundIn(data) {
        case .head(let request):
            do {
                context.write(wrapOutboundOut(.head(try request.newRequest(secure: secure, splitCookie: splitCookie))), promise: promise)
            } catch {
                context.fireErrorCaught(error)
            }
        case .body(let body):
            context.write(wrapOutboundOut(.body(body)), promise: promise)
        case .end(let trailers):
            context.write(wrapOutboundOut(.end(trailers?.newFields(splitCookie: false))), promise: promise)
        }
    }
}

/// A simple channel handler that translates shared HTTP types into HTTP/1 messages,
/// and vice versa, for use on the server side.
///
/// This is intended for compatibility purposes where a channel handler working with
/// HTTP/1 messages needs to work on top of the new version-independent HTTP types
/// abstraction.
public final class HTTPToHTTP1ServerCodec: ChannelInboundHandler, ChannelOutboundHandler {
    public typealias InboundIn = HTTPTypeServerRequestPart
    public typealias InboundOut = HTTPServerRequestPart

    public typealias OutboundIn = HTTPServerResponsePart
    public typealias OutboundOut = HTTPTypeServerResponsePart

    /// Initializes a `HTTPToHTTP1ServerCodec`.
    public init() {
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            do {
                context.fireChannelRead(wrapInboundOut(.head(try HTTPRequestHead(head))))
            } catch {
                context.fireErrorCaught(error)
            }
        case .body(let body):
            context.fireChannelRead(wrapInboundOut(.body(body)))
        case .end(let trailers):
            context.fireChannelRead(wrapInboundOut(.end(trailers.map(HTTPHeaders.init))))
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        switch unwrapOutboundIn(data) {
        case .head(let response):
            do {
                context.write(wrapOutboundOut(.head(try response.newResponse)), promise: promise)
            } catch {
                context.fireErrorCaught(error)
            }
        case .body(let body):
            context.write(wrapOutboundOut(.body(body)), promise: promise)
        case .end(let trailers):
            context.write(wrapOutboundOut(.end(trailers?.newFields(splitCookie: false))), promise: promise)
        }
    }
}
