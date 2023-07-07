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
    public typealias InboundIn = HTTPTypeResponsePart
    public typealias InboundOut = HTTPClientResponsePart

    public typealias OutboundIn = HTTPClientRequestPart
    public typealias OutboundOut = HTTPTypeRequestPart

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
        switch self.unwrapInboundIn(data) {
        case .head(let head):
            context.fireChannelRead(self.wrapInboundOut(.head(HTTPResponseHead(head))))
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
                try context.write(self.wrapOutboundOut(.head(request.newRequest(secure: self.secure, splitCookie: self.splitCookie))), promise: promise)
            } catch {
                context.fireErrorCaught(error)
            }
        case .body(.byteBuffer(let body)):
            context.write(self.wrapOutboundOut(.body(body)), promise: promise)
        case .body:
            fatalError("File region not supported")
        case .end(let trailers):
            context.write(self.wrapOutboundOut(.end(trailers?.newFields(splitCookie: false))), promise: promise)
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
    public typealias InboundIn = HTTPTypeRequestPart
    public typealias InboundOut = HTTPServerRequestPart

    public typealias OutboundIn = HTTPServerResponsePart
    public typealias OutboundOut = HTTPTypeResponsePart

    /// Initializes a `HTTPToHTTP1ServerCodec`.
    public init() {}

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.unwrapInboundIn(data) {
        case .head(let head):
            do {
                try context.fireChannelRead(self.wrapInboundOut(.head(HTTPRequestHead(head))))
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
                try context.write(self.wrapOutboundOut(.head(response.newResponse)), promise: promise)
            } catch {
                context.fireErrorCaught(error)
            }
        case .body(.byteBuffer(let body)):
            context.write(self.wrapOutboundOut(.body(body)), promise: promise)
        case .body:
            fatalError("File region not supported")
        case .end(let trailers):
            context.write(self.wrapOutboundOut(.end(trailers?.newFields(splitCookie: false))), promise: promise)
        }
    }
}
