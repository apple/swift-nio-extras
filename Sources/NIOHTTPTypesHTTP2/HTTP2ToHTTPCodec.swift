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

    mutating func processInboundData(_ data: HTTP2Frame.FramePayload) throws -> (first: HTTPTypeClientResponsePart?, second: HTTPTypeClientResponsePart?) {
        switch data {
        case .headers(let headerContent):
            switch try self.headerStateMachine.newHeaders(block: headerContent.headers) {
            case .trailer:
                return try (first: .end(headerContent.headers.newTrailers), second: nil)

            case .informationalResponseHead:
                return try (first: .head(headerContent.headers.newResponse), second: nil)

            case .finalResponseHead:
                guard self.outgoingHTTP1RequestHead != nil else {
                    preconditionFailure("Expected not to get a response without having sent a request")
                }
                self.outgoingHTTP1RequestHead = nil
                let respHead = try headerContent.headers.newResponse
                let first = HTTPTypeClientResponsePart.head(respHead)
                var second: HTTPTypeClientResponsePart?
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

            var first = HTTPTypeClientResponsePart.body(b)
            var second: HTTPTypeClientResponsePart?
            if content.endStream {
                if b.readableBytes == 0 {
                    first = .end(nil)
                } else {
                    second = .end(nil)
                }
            }
            return (first: first, second: second)
        case .alternativeService, .rstStream, .priority, .windowUpdate, .settings, .pushPromise, .ping, .goAway, .origin:
            // These are not meaningful in HTTP messaging, so drop them.
            return (first: nil, second: nil)
        }
    }

    mutating func processOutboundData(_ data: HTTPTypeClientRequestPart, allocator: ByteBufferAllocator) throws -> HTTP2Frame.FramePayload {
        switch data {
        case .head(let head):
            precondition(self.outgoingHTTP1RequestHead == nil, "Only a single HTTP request allowed per HTTP2 stream")
            self.outgoingHTTP1RequestHead = head
            let headerContent = HTTP2Frame.FramePayload.Headers(headers: HPACKHeaders(head))
            return .headers(headerContent)
        case .body(let body):
            return .data(HTTP2Frame.FramePayload.Data(data: body))
        case .end(let trailers):
            if let trailers {
                return .headers(.init(
                    headers: HPACKHeaders(trailers),
                    endStream: true
                ))
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
public final class HTTP2FramePayloadToHTTPClientCodec: ChannelInboundHandler, ChannelOutboundHandler {
    public typealias InboundIn = HTTP2Frame.FramePayload
    public typealias InboundOut = HTTPTypeClientResponsePart

    public typealias OutboundIn = HTTPTypeClientRequestPart
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
            let transformedPayload = try self.baseCodec.processOutboundData(requestPart, allocator: context.channel.allocator)
            context.write(self.wrapOutboundOut(transformedPayload), promise: promise)
        } catch {
            promise?.fail(error)
            context.fireErrorCaught(error)
        }
    }
}

// MARK: - Server

private struct BaseServerCodec {
    private var headerStateMachine: HTTP2HeadersStateMachine = .init(mode: .server)

    mutating func processInboundData(_ data: HTTP2Frame.FramePayload) throws -> (first: HTTPTypeServerRequestPart?, second: HTTPTypeServerRequestPart?) {
        switch data {
        case .headers(let headerContent):
            if case .trailer = try self.headerStateMachine.newHeaders(block: headerContent.headers) {
                return try (first: .end(headerContent.headers.newTrailers), second: nil)
            } else {
                let reqHead = try headerContent.headers.newRequest

                let first = HTTPTypeServerRequestPart.head(reqHead)
                var second: HTTPTypeServerRequestPart?
                if headerContent.endStream {
                    second = .end(nil)
                }
                return (first: first, second: second)
            }
        case .data(let dataContent):
            guard case .byteBuffer(let b) = dataContent.data else {
                preconditionFailure("Received non-byteBuffer IOData from network")
            }
            var first = HTTPTypeServerRequestPart.body(b)
            var second: HTTPTypeServerRequestPart?
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

    mutating func processOutboundData(_ data: HTTPTypeServerResponsePart, allocator: ByteBufferAllocator) -> HTTP2Frame.FramePayload {
        switch data {
        case .head(let head):
            let payload = HTTP2Frame.FramePayload.Headers(headers: HPACKHeaders(head))
            return .headers(payload)
        case .body(let body):
            let payload = HTTP2Frame.FramePayload.Data(data: body)
            return .data(payload)
        case .end(let trailers):
            if let trailers {
                return .headers(.init(
                    headers: HPACKHeaders(trailers),
                    endStream: true
                ))
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
public final class HTTP2FramePayloadToHTTPServerCodec: ChannelInboundHandler, ChannelOutboundHandler {
    public typealias InboundIn = HTTP2Frame.FramePayload
    public typealias InboundOut = HTTPTypeServerRequestPart

    public typealias OutboundIn = HTTPTypeServerResponsePart
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
}
