//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOHTTPTypes

/// A channel handler that translates resumable uploads into regular uploads, and passes through
/// other HTTP traffic.
public final class HTTPResumableUploadHandler: ChannelDuplexHandler {
    public typealias InboundIn = HTTPRequestPart
    public typealias InboundOut = Never

    public typealias OutboundIn = Never
    public typealias OutboundOut = HTTPResponsePart

    var upload: HTTPResumableUpload.SendableView? = nil
    let createUpload: () -> HTTPResumableUpload
    var shouldReset: Bool = false

    private var context: ChannelHandlerContext?
    private var eventLoop: EventLoop!

    /// Create an `HTTPResumableUploadHandler` within a given `HTTPResumableUploadContext`.
    /// - Parameters:
    ///   - context: The context for this upload handler.
    ///              Use the same context across upload handlers, as uploads can't resume across different contexts.
    ///   - channelConfigurator: A closure for configuring the child HTTP server channel.
    public init(
        context: HTTPResumableUploadContext,
        channelConfigurator: @escaping (Channel) -> Void
    ) {
        self.createUpload = {
            HTTPResumableUpload(
                context: context,
                channelConfigurator: channelConfigurator
            )
        }
    }

    /// Create an `HTTPResumableUploadHandler` within a given `HTTPResumableUploadContext`.
    /// - Parameters:
    ///   - context: The context for this upload handler.
    ///              Use the same context across upload handlers, as uploads can't resume across different contexts.
    ///   - handlers: Handlers to add to the child HTTP server channel.
    public init(
        context: HTTPResumableUploadContext,
        handlers: [ChannelHandler] = []
    ) {
        self.createUpload = {
            HTTPResumableUpload(context: context) { channel in
                if !handlers.isEmpty {
                    try? channel.pipeline.syncOperations.addHandlers(handlers)
                }
            }
        }
    }

    private func resetUpload(context: ChannelHandlerContext) {
        if let existingUpload = self.upload {
            existingUpload.end(handler: self, error: nil)
        }
        let upload = self.createUpload()
        upload.scheduleOnEventLoop(self.eventLoop)
        upload.attachUploadHandler(self.sendableView, channel: context.channel)
        self.upload = upload.sendableView
        self.shouldReset = false
    }

    public func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        self.eventLoop = context.eventLoop

        self.resetUpload(context: context)
    }

    public func channelActive(context: ChannelHandlerContext) {
        context.read()
    }

    public func channelInactive(context: ChannelHandlerContext) {
        self.upload?.end(handler: self, error: nil)
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if self.shouldReset {
            self.resetUpload(context: context)
        }
        let part = self.unwrapInboundIn(data)
        if case .end = part {
            self.shouldReset = true
        }
        self.upload?.receive(handler: self, channel: context.channel, part: part)
    }

    public func channelReadComplete(context: ChannelHandlerContext) {
        self.upload?.receiveComplete(handler: self)
    }

    public func channelWritabilityChanged(context: ChannelHandlerContext) {
        self.upload?.writabilityChanged(handler: self)
    }

    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {}

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.upload?.end(handler: self, error: error)
    }

    public func read(context: ChannelHandlerContext) {
        if self.shouldReset {
            context.read()
        }
    }
}

@available(*, unavailable)
extension HTTPResumableUploadHandler: Sendable {}

// For `HTTPResumableUpload`.
extension HTTPResumableUploadHandler {
    func write(_ part: HTTPResponsePart, promise: EventLoopPromise<Void>?) {
        self.context?.write(self.wrapOutboundOut(part), promise: promise)
    }

    func flush() {
        self.context?.flush()
    }

    func writeAndFlush(_ part: HTTPResponsePart, promise: EventLoopPromise<Void>?) {
        self.context?.writeAndFlush(self.wrapOutboundOut(part), promise: promise)
    }

    func read() {
        self.context?.read()
    }

    func close(mode: CloseMode, promise: EventLoopPromise<Void>?) {
        self.context?.close(mode: mode, promise: promise)
    }

    func detach() {
        self.context = nil
    }
}

extension HTTPResumableUploadHandler {
    var sendableView: SendableView {
        SendableView(self)
    }

    struct SendableView: Sendable {
        private let handler: NIOLoopBound<HTTPResumableUploadHandler>
        let id: ObjectIdentifier

        fileprivate init(_ handler: HTTPResumableUploadHandler) {
            self.handler = NIOLoopBound(handler, eventLoop: handler.eventLoop)
            self.id = ObjectIdentifier(handler)
        }

        func withHandler(_ body: @Sendable @escaping (HTTPResumableUploadHandler) -> Void) {
            if self.handler.eventLoop.inEventLoop {
                body(self.handler.value)
            } else {
                self.handler.eventLoop.execute {
                    body(self.handler.value)
                }
            }
        }

        func write(_ part: HTTPResponsePart, promise: EventLoopPromise<Void>?) {
            self.withHandler {
                $0.context?.write($0.wrapOutboundOut(part), promise: promise)
            }
        }

        func flush() {
            self.withHandler {
                $0.context?.flush()
            }
        }

        func writeAndFlush(_ part: HTTPResponsePart, promise: EventLoopPromise<Void>?) {
            self.withHandler {
                $0.context?.writeAndFlush($0.wrapOutboundOut(part), promise: promise)
            }
        }

        func read() {
            self.withHandler {
                $0.context?.read()
            }
        }

        func close(mode: CloseMode, promise: EventLoopPromise<Void>?) {
            self.withHandler {
                $0.context?.close(mode: mode, promise: promise)
            }
        }

        func detach() {
            self.withHandler {
                $0.context = nil
            }
        }
    }
}
