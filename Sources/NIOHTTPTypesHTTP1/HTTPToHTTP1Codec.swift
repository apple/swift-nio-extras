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

import HTTPTypes
import NIOCore
import NIOHTTP1
import NIOHTTPTypes

/// A simple channel handler that translates shared HTTP types into HTTP/1 messages,
/// and vice versa, for use on the client side.
///
/// This is intended for compatibility purposes where a channel handler working with
/// HTTP/1 messages needs to work on top of the new version-independent HTTP types
/// abstraction.
public final class HTTPToHTTP1ClientCodec: ChannelDuplexHandler, RemovableChannelHandler, Sendable {
    public typealias InboundIn = HTTPResponsePart
    public typealias InboundOut = HTTPClientResponsePart

    public typealias OutboundIn = HTTPClientRequestPart
    public typealias OutboundOut = HTTPRequestPart

    private let secure: Bool
    private let splitCookie: Bool

    /// Initializes a `HTTPToHTTP1ClientCodec`.
    /// - Parameters:
    ///   - secure: Whether "https" or "http" is used.
    ///   - splitCookie: Whether the cookies sent by the client should be split
    ///                  into multiple header fields. Splitting the `Cookie`
    ///                  header field improves the performance of HTTP/2 and
    ///                  HTTP/3 clients by allowing individual cookies to be
    ///                  indexed separately in the dynamic table. It has no
    ///                  effects in HTTP/1. Defaults to true.
    public init(secure: Bool, splitCookie: Bool = true) {
        self.secure = secure
        self.splitCookie = splitCookie
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.unwrapInboundIn(data) {
        case .head(let head):
            let oldResponse = HTTPResponseHead(head)
            context.fireChannelRead(self.wrapInboundOut(.head(oldResponse)))
        case .body(let body):
            context.fireChannelRead(self.wrapInboundOut(.body(body)))
        case .end(let trailers):
            context.fireChannelRead(self.wrapInboundOut(.end(trailers.map(HTTPHeaders.init))))
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        switch self.unwrapOutboundIn(data) {
        case .head(let request):
            do {
                let newRequest = try HTTPRequest(request, secure: self.secure, splitCookie: self.splitCookie)
                context.write(self.wrapOutboundOut(.head(newRequest)), promise: promise)
            } catch {
                context.fireErrorCaught(error)
                promise?.fail(error)
            }
        case .body(.byteBuffer(let body)):
            context.write(self.wrapOutboundOut(.body(body)), promise: promise)
        case .body:
            fatalError("File region not supported")
        case .end(let trailers):
            let newTrailers = trailers.map { HTTPFields($0, splitCookie: false) }
            context.write(self.wrapOutboundOut(.end(newTrailers)), promise: promise)
        }
    }
}

/// A simple channel handler that translates shared HTTP types into HTTP/1 messages,
/// and vice versa, for use on the server side.
///
/// This is intended for compatibility purposes where a channel handler working with
/// HTTP/1 messages needs to work on top of the new version-independent HTTP types
/// abstraction.
public final class HTTPToHTTP1ServerCodec: ChannelDuplexHandler, RemovableChannelHandler, Sendable {
    public typealias InboundIn = HTTPRequestPart
    public typealias InboundOut = HTTPServerRequestPart

    public typealias OutboundIn = HTTPServerResponsePart
    public typealias OutboundOut = HTTPResponsePart

    private let absoluteForm: Bool

    /// Initializes a `HTTPToHTTP1ServerCodec`.
    public init() {
        self.absoluteForm = false
    }

    /// Initializes a `HTTPToHTTP1ServerCodec`.
    /// - Parameters:
    ///   - absoluteForm: Whether the request should use the absolute-form (for cleartext HTTP proxies).
    public init(absoluteForm: Bool) {
        self.absoluteForm = absoluteForm
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.unwrapInboundIn(data) {
        case .head(let head):
            do {
                let oldRequest = try HTTPRequestHead(head, absoluteForm: self.absoluteForm)
                context.fireChannelRead(self.wrapInboundOut(.head(oldRequest)))
            } catch {
                context.fireErrorCaught(error)
            }
        case .body(let body):
            context.fireChannelRead(self.wrapInboundOut(.body(body)))
        case .end(let trailers):
            context.fireChannelRead(self.wrapInboundOut(.end(trailers.map(HTTPHeaders.init))))
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        switch self.unwrapOutboundIn(data) {
        case .head(let response):
            do {
                let newResponse = try HTTPResponse(response)
                context.write(self.wrapOutboundOut(.head(newResponse)), promise: promise)
            } catch {
                context.fireErrorCaught(error)
                promise?.fail(error)
            }
        case .body(.byteBuffer(let body)):
            context.write(self.wrapOutboundOut(.body(body)), promise: promise)
        case .body:
            fatalError("File region not supported")
        case .end(let trailers):
            let newTrailers = trailers.map { HTTPFields($0, splitCookie: false) }
            context.write(self.wrapOutboundOut(.end(newTrailers)), promise: promise)
        }
    }
}
