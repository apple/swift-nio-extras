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
import NIOHPACK
import NIOHTTP2
import NIOHTTPTypes

// MARK: - Client

private struct BaseClientCodec {
    private var headerStateMachine: HTTP2HeadersStateMachine = .init(mode: .client)

    private var outgoingHTTP1RequestHead: HTTPRequest?

    mutating func processInboundData(
        _ data: HTTP2Frame.FramePayload
    ) throws -> (first: HTTPResponsePart?, second: HTTPResponsePart?) {
        switch data {
        case .headers(let headerContent):
            switch try self.headerStateMachine.newHeaders(block: headerContent.headers) {
            case .trailer:
                let newTrailers = try HTTPFields(trailers: headerContent.headers)
                return (first: .end(newTrailers), second: nil)

            case .informationalResponseHead:
                let newResponse = try HTTPResponse(headerContent.headers)
                return (first: .head(newResponse), second: nil)

            case .finalResponseHead:
                guard self.outgoingHTTP1RequestHead != nil else {
                    preconditionFailure("Expected not to get a response without having sent a request")
                }
                self.outgoingHTTP1RequestHead = nil
                let newResponse = try HTTPResponse(headerContent.headers)
                let first = HTTPResponsePart.head(newResponse)
                var second: HTTPResponsePart?
                if headerContent.endStream {
                    second = .end(nil)
                }
                return (first: first, second: second)

            case .requestHead:
                preconditionFailure("A client can not receive request heads")
            }
        case .data(let content):
            guard case .byteBuffer(let b) = content.data else {
                preconditionFailure("Received DATA frame with non-bytebuffer IOData")
            }

            var first = HTTPResponsePart.body(b)
            var second: HTTPResponsePart?
            if content.endStream {
                if b.readableBytes == 0 {
                    first = .end(nil)
                } else {
                    second = .end(nil)
                }
            }
            return (first: first, second: second)
        case .alternativeService, .rstStream, .priority, .windowUpdate, .settings, .pushPromise, .ping, .goAway,
            .origin:
            // These are not meaningful in HTTP messaging, so drop them.
            return (first: nil, second: nil)
        }
    }

    mutating func processOutboundData(
        _ data: HTTPRequestPart,
        allocator: ByteBufferAllocator
    ) throws -> HTTP2Frame.FramePayload {
        switch data {
        case .head(let head):
            precondition(self.outgoingHTTP1RequestHead == nil, "Only a single HTTP request allowed per HTTP2 stream")
            self.outgoingHTTP1RequestHead = head
            let headerContent = HTTP2Frame.FramePayload.Headers(headers: HPACKHeaders(head))
            return .headers(headerContent)
        case .body(let body):
            return .data(HTTP2Frame.FramePayload.Data(data: .byteBuffer(body)))
        case .end(let trailers):
            if let trailers {
                return .headers(
                    .init(
                        headers: HPACKHeaders(trailers),
                        endStream: true
                    )
                )
            } else {
                return .data(.init(data: .byteBuffer(allocator.buffer(capacity: 0)), endStream: true))
            }
        }
    }
}

/// A simple channel handler that translates HTTP/2 concepts into shared HTTP types,
/// and vice versa, for use on the client side.
///
/// Use this channel handler alongside the `HTTP2StreamMultiplexer` to
/// help provide an HTTP transaction-level abstraction on top of an HTTP/2 multiplexed
/// connection.
///
/// This handler uses `HTTP2Frame.FramePayload` as its HTTP/2 currency type.
public final class HTTP2FramePayloadToHTTPClientCodec: ChannelDuplexHandler, RemovableChannelHandler {
    public typealias InboundIn = HTTP2Frame.FramePayload
    public typealias InboundOut = HTTPResponsePart

    public typealias OutboundIn = HTTPRequestPart
    public typealias OutboundOut = HTTP2Frame.FramePayload

    private var baseCodec: BaseClientCodec = .init()

    public init() {}

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let payload = self.unwrapInboundIn(data)
        do {
            let (first, second) = try self.baseCodec.processInboundData(payload)
            if let first {
                context.fireChannelRead(self.wrapInboundOut(first))
            }
            if let second {
                context.fireChannelRead(self.wrapInboundOut(second))
            }
        } catch {
            context.fireErrorCaught(error)
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let requestPart = self.unwrapOutboundIn(data)

        do {
            let transformedPayload = try self.baseCodec.processOutboundData(
                requestPart,
                allocator: context.channel.allocator
            )
            context.write(self.wrapOutboundOut(transformedPayload), promise: promise)
        } catch {
            promise?.fail(error)
            context.fireErrorCaught(error)
        }
    }

    public func triggerUserOutboundEvent(context: ChannelHandlerContext, event: Any, promise: EventLoopPromise<Void>?) {
        if let ev = event as? NIOHTTP2FramePayloadToHTTPEvent, let code = ev.reset {
            context.writeAndFlush(self.wrapOutboundOut(.rstStream(code)), promise: promise)
            return
        }
        context.triggerUserOutboundEvent(event, promise: promise)
    }
}

@available(*, unavailable)
extension HTTP2FramePayloadToHTTPClientCodec: Sendable {}

// MARK: - Server

private struct BaseServerCodec {
    private var headerStateMachine: HTTP2HeadersStateMachine = .init(mode: .server)

    mutating func processInboundData(
        _ data: HTTP2Frame.FramePayload
    ) throws -> (first: HTTPRequestPart?, second: HTTPRequestPart?) {
        switch data {
        case .headers(let headerContent):
            if case .trailer = try self.headerStateMachine.newHeaders(block: headerContent.headers) {
                let newTrailers = try HTTPFields(trailers: headerContent.headers)
                return (first: .end(newTrailers), second: nil)
            } else {
                let newRequest = try HTTPRequest(headerContent.headers)
                let first = HTTPRequestPart.head(newRequest)
                var second: HTTPRequestPart?
                if headerContent.endStream {
                    second = .end(nil)
                }
                return (first: first, second: second)
            }
        case .data(let dataContent):
            guard case .byteBuffer(let b) = dataContent.data else {
                preconditionFailure("Received non-byteBuffer IOData from network")
            }
            var first = HTTPRequestPart.body(b)
            var second: HTTPRequestPart?
            if dataContent.endStream {
                if b.readableBytes == 0 {
                    first = .end(nil)
                } else {
                    second = .end(nil)
                }
            }
            return (first: first, second: second)
        default:
            // Any other frame type is ignored.
            return (first: nil, second: nil)
        }
    }

    mutating func processOutboundData(
        _ data: HTTPResponsePart,
        allocator: ByteBufferAllocator
    ) -> HTTP2Frame.FramePayload {
        switch data {
        case .head(let head):
            let payload = HTTP2Frame.FramePayload.Headers(headers: HPACKHeaders(head))
            return .headers(payload)
        case .body(let body):
            let payload = HTTP2Frame.FramePayload.Data(data: .byteBuffer(body))
            return .data(payload)
        case .end(let trailers):
            if let trailers {
                return .headers(
                    .init(
                        headers: HPACKHeaders(trailers),
                        endStream: true
                    )
                )
            } else {
                return .data(.init(data: .byteBuffer(allocator.buffer(capacity: 0)), endStream: true))
            }
        }
    }
}

/// A simple channel handler that translates HTTP/2 concepts into shared HTTP types,
/// and vice versa, for use on the server side.
///
/// Use this channel handler alongside the `HTTP2StreamMultiplexer` to
/// help provide an HTTP transaction-level abstraction on top of an HTTP/2 multiplexed
/// connection.
///
/// This handler uses `HTTP2Frame.FramePayload` as its HTTP/2 currency type.
public final class HTTP2FramePayloadToHTTPServerCodec: ChannelDuplexHandler, RemovableChannelHandler {
    public typealias InboundIn = HTTP2Frame.FramePayload
    public typealias InboundOut = HTTPRequestPart

    public typealias OutboundIn = HTTPResponsePart
    public typealias OutboundOut = HTTP2Frame.FramePayload

    private var baseCodec: BaseServerCodec = .init()

    public init() {}

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let payload = self.unwrapInboundIn(data)

        do {
            let (first, second) = try self.baseCodec.processInboundData(payload)
            if let first {
                context.fireChannelRead(self.wrapInboundOut(first))
            }
            if let second {
                context.fireChannelRead(self.wrapInboundOut(second))
            }
        } catch {
            context.fireErrorCaught(error)
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let responsePart = self.unwrapOutboundIn(data)
        let transformedPayload = self.baseCodec.processOutboundData(responsePart, allocator: context.channel.allocator)
        context.write(self.wrapOutboundOut(transformedPayload), promise: promise)
    }

    public func triggerUserOutboundEvent(context: ChannelHandlerContext, event: Any, promise: EventLoopPromise<Void>?) {
        if let ev = event as? NIOHTTP2FramePayloadToHTTPEvent, let code = ev.reset {
            context.writeAndFlush(self.wrapOutboundOut(.rstStream(code)), promise: promise)
            return
        }
        context.triggerUserOutboundEvent(event, promise: promise)
    }
}

@available(*, unavailable)
extension HTTP2FramePayloadToHTTPServerCodec: Sendable {}

/// Events that can be sent by the application to be handled by the `HTTP2StreamChannel`
public struct NIOHTTP2FramePayloadToHTTPEvent: Hashable, Sendable {
    private enum Kind: Hashable, Sendable {
        case reset(HTTP2ErrorCode)
    }

    private var kind: Kind

    /// Send a `RST_STREAM` with the specified code
    public static func reset(code: HTTP2ErrorCode) -> Self {
        .init(kind: .reset(code))
    }

    /// Returns reset code if the event is a reset
    public var reset: HTTP2ErrorCode? {
        switch self.kind {
        case .reset(let code):
            return code
        }
    }
}
