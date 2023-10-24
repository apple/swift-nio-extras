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
import NIOHTTPTypes

/// A channel handler that translates resumable uploads into regular uploads, and passes through
/// other HTTP traffic.
public final class HTTPResumableUploadHandler: ChannelDuplexHandler {
    public typealias InboundIn = HTTPRequestPart
    public typealias InboundOut = Never

    public typealias OutboundIn = Never
    public typealias OutboundOut = HTTPResponsePart

    var upload: HTTPResumableUpload

    private var context: ChannelHandlerContext!
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
        self.upload = HTTPResumableUpload(
            context: context,
            channelConfigurator: channelConfigurator
        )
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
        self.upload = HTTPResumableUpload(context: context) { channel in
            if !handlers.isEmpty {
                _ = channel.pipeline.addHandlers(handlers)
            }
        }
    }

    public func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        self.eventLoop = context.eventLoop

        self.upload.scheduleOnEventLoop(context.eventLoop)
        self.upload.attachUploadHandler(self, channel: context.channel)
    }

    public func channelActive(context: ChannelHandlerContext) {
        context.read()
    }

    public func channelInactive(context: ChannelHandlerContext) {
        self.upload.end(handler: self, error: nil)
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.upload.receive(handler: self, channel: self.context.channel, part: unwrapInboundIn(data))
    }

    public func channelReadComplete(context: ChannelHandlerContext) {
        self.upload.receiveComplete(handler: self)
    }

    public func channelWritabilityChanged(context: ChannelHandlerContext) {
        self.upload.writabilityChanged(handler: self)
    }

    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {}

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.upload.end(handler: self, error: error)
    }

    public func read(context: ChannelHandlerContext) {
        // Do nothing.
    }
}

// For `HTTPResumableUpload`.
extension HTTPResumableUploadHandler {
    private func runInEventLoop(_ work: @escaping () -> Void) {
        if self.eventLoop.inEventLoop {
            work()
        } else {
            self.eventLoop.execute(work)
        }
    }

    func write(_ part: HTTPResponsePart, promise: EventLoopPromise<Void>?) {
        self.runInEventLoop {
            self.context.write(self.wrapOutboundOut(part), promise: promise)
        }
    }

    func flush() {
        self.runInEventLoop {
            self.context.flush()
        }
    }

    func writeAndFlush(_ part: HTTPResponsePart, promise: EventLoopPromise<Void>?) {
        self.runInEventLoop {
            self.context.writeAndFlush(self.wrapOutboundOut(part), promise: promise)
        }
    }

    func read() {
        self.runInEventLoop {
            self.context.read()
        }
    }

    func close(mode: CloseMode, promise: EventLoopPromise<Void>?) {
        self.runInEventLoop {
            self.context.close(mode: mode, promise: promise)
        }
    }
}
