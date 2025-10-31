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

/// A simple channel handler that translates HTTP/1 messages into shared HTTP types,
/// and vice versa, for use on the client side.
public final class HTTP1ToHTTPClientCodec: ChannelDuplexHandler, RemovableChannelHandler, Sendable {
    public typealias InboundIn = HTTPClientResponsePart
    public typealias InboundOut = HTTPResponsePart

    public typealias OutboundIn = HTTPRequestPart
    public typealias OutboundOut = HTTPClientRequestPart

    private let absoluteForm: Bool

    /// Initializes a `HTTP1ToHTTPClientCodec`.
    public init() {
        self.absoluteForm = false
    }

    /// Initializes a `HTTP1ToHTTPClientCodec`.
    /// - Parameters:
    ///   - absoluteForm: Whether the request should use the absolute-form (for cleartext HTTP proxies).
    public init(absoluteForm: Bool) {
        self.absoluteForm = absoluteForm
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.unwrapInboundIn(data) {
        case .head(let head):
            do {
                let newResponse = try HTTPResponse(head)
                context.fireChannelRead(self.wrapInboundOut(.head(newResponse)))
            } catch {
                context.fireErrorCaught(error)
            }
        case .body(let body):
            context.fireChannelRead(self.wrapInboundOut(.body(body)))
        case .end(let trailers):
            let newTrailers = trailers.map { HTTPFields($0, splitCookie: false) }
            context.fireChannelRead(self.wrapInboundOut(.end(newTrailers)))
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        switch self.unwrapOutboundIn(data) {
        case .head(let request):
            do {
                let oldRequest = try HTTPRequestHead(request, absoluteForm: self.absoluteForm)
                context.write(self.wrapOutboundOut(.head(oldRequest)), promise: promise)
            } catch {
                context.fireErrorCaught(error)
                promise?.fail(error)
            }
        case .body(let body):
            context.write(self.wrapOutboundOut(.body(.byteBuffer(body))), promise: promise)
        case .end(let trailers):
            context.write(self.wrapOutboundOut(.end(trailers.map(HTTPHeaders.init))), promise: promise)
        }
    }
}

/// A simple channel handler that translates HTTP/1 messages into shared HTTP types,
/// and vice versa, for use on the server side.
public final class HTTP1ToHTTPServerCodec: ChannelDuplexHandler, RemovableChannelHandler, Sendable {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias InboundOut = HTTPRequestPart

    public typealias OutboundIn = HTTPResponsePart
    public typealias OutboundOut = HTTPServerResponsePart

    private let secure: Bool
    private let splitCookie: Bool

    /// Initializes a `HTTP1ToHTTPServerCodec`.
    /// - Parameters:
    ///   - secure: Whether "https" or "http" is used.
    ///   - splitCookie: Whether the cookies received from the server should be split
    ///                  into multiple header fields. Defaults to false.
    public init(secure: Bool, splitCookie: Bool = false) {
        self.secure = secure
        self.splitCookie = splitCookie
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.unwrapInboundIn(data) {
        case .head(let head):
            do {
                let newRequest = try HTTPRequest(head, secure: self.secure, splitCookie: self.splitCookie)
                context.fireChannelRead(self.wrapInboundOut(.head(newRequest)))
            } catch {
                context.fireErrorCaught(error)
            }
        case .body(let body):
            context.fireChannelRead(self.wrapInboundOut(.body(body)))
        case .end(let trailers):
            let newTrailers = trailers.map { HTTPFields($0, splitCookie: false) }
            context.fireChannelRead(self.wrapInboundOut(.end(newTrailers)))
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        switch self.unwrapOutboundIn(data) {
        case .head(let response):
            let oldResponse = HTTPResponseHead(response)
            context.write(self.wrapOutboundOut(.head(oldResponse)), promise: promise)
        case .body(let body):
            context.write(self.wrapOutboundOut(.body(.byteBuffer(body))), promise: promise)
        case .end(let trailers):
            context.write(self.wrapOutboundOut(.end(trailers.map(HTTPHeaders.init))), promise: promise)
        }
    }
}
