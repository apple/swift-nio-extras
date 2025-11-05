//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2024 Apple Inc. and the SwiftNIO project authors
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
import NIOHTTPTypes

/// HTTP request handler sending a configurable stream of zeroes. Uses HTTPTypes request/response parts.
public final class HTTPDrippingDownloadHandler: ChannelDuplexHandler {
    public typealias InboundIn = HTTPRequestPart
    public typealias OutboundOut = HTTPResponsePart
    public typealias OutboundIn = Never

    // Predefine buffer to reuse over and over again when sending chunks to requester.  NIO allows
    // us to give it reference counted buffers. Reusing like this allows us to avoid allocations.
    static let downloadBodyChunk = ByteBuffer(repeating: 0, count: 65536)

    private var frequency: TimeAmount
    private var size: Int
    private var count: Int
    private var delay: TimeAmount
    private var code: HTTPResponse.Status

    private enum Phase {
        /// We haven't gotten the request head - nothing to respond to
        case waitingOnHead
        /// We got the request head and are delaying the response
        case delayingResponse
        /// We're dripping response chunks to the peer, tracking how many chunks we have left
        case dripping(DrippingState)
        /// We either sent everything to the client or the request ended short
        case done
    }

    private struct DrippingState {
        var chunksLeft: Int
        var currentChunkBytesLeft: Int
    }

    private var phase = Phase.waitingOnHead
    private var scheduled: Scheduled<Void>?
    private var scheduledCallbackHandler: HTTPDrippingDownloadHandlerScheduledCallbackHandler?
    private var pendingRead = false
    private var pendingWrite = false
    private var activelyWritingChunk = false

    /// Initializes an `HTTPDrippingDownloadHandler`.
    /// - Parameters:
    ///   - count: How many chunks should be sent. Note that the underlying HTTP
    ///            stack may split or combine these chunks into data frames as
    ///            they see fit.
    ///   - size: How large each chunk should be
    ///   - frequency: How much time to wait between sending each chunk
    ///   - delay: How much time to wait before sending the first chunk
    ///   - code: What HTTP status code to send
    public init(
        count: Int = 0,
        size: Int = 0,
        frequency: TimeAmount = .zero,
        delay: TimeAmount = .zero,
        code: HTTPResponse.Status = .ok
    ) {
        self.frequency = frequency
        self.size = size
        self.count = count
        self.delay = delay
        self.code = code
    }

    public convenience init?(queryArgsString: Substring.UTF8View) {
        self.init()

        let pairs = queryArgsString.split(separator: UInt8(ascii: "&"))
        for pair in pairs {
            var pairParts = pair.split(separator: UInt8(ascii: "="), maxSplits: 1).makeIterator()
            guard let first = pairParts.next(), let second = pairParts.next() else {
                continue
            }

            guard let secondNum = Int(Substring(second)) else {
                return nil
            }

            switch Substring(first) {
            case "frequency":
                self.frequency = .seconds(Int64(secondNum))
            case "size":
                self.size = secondNum
            case "count":
                self.count = secondNum
            case "delay":
                self.delay = .seconds(Int64(secondNum))
            case "code":
                self.code = HTTPResponse.Status(code: secondNum)
            default:
                continue
            }
        }
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = self.unwrapInboundIn(data)

        switch part {
        case .head:
            self.phase = .delayingResponse

            if self.delay == TimeAmount.zero {
                // If no delay, we might as well start responding immediately
                self.onResponseDelayCompleted(context: context)
            } else {
                let this = NIOLoopBound(self, eventLoop: context.eventLoop)
                let loopBoundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
                self.scheduled = context.eventLoop.scheduleTask(in: self.delay) {
                    this.value.onResponseDelayCompleted(context: loopBoundContext.value)
                }
            }
        case .body, .end:
            return
        }
    }

    private func onResponseDelayCompleted(context: ChannelHandlerContext) {
        guard case .delayingResponse = self.phase else {
            return
        }

        var head = HTTPResponse(status: self.code)

        // If the length isn't too big, let's include a content length header
        if case (let contentLength, false) = self.size.multipliedReportingOverflow(by: self.count) {
            head.headerFields[.contentLength] = "\(contentLength)"
        }

        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        self.phase = .dripping(
            DrippingState(
                chunksLeft: self.count,
                currentChunkBytesLeft: self.size
            )
        )

        self.writeChunk(context: context)
    }

    public func channelInactive(context: ChannelHandlerContext) {
        self.phase = .done
        self.scheduled?.cancel()
        context.fireChannelInactive()
    }

    public func channelWritabilityChanged(context: ChannelHandlerContext) {
        if case .dripping = self.phase, self.pendingWrite && context.channel.isWritable {
            self.writeChunk(context: context)
        }
    }

    private func writeChunk(context: ChannelHandlerContext) {
        // Make sure we don't accidentally reenter
        if self.activelyWritingChunk {
            return
        }
        self.activelyWritingChunk = true
        defer {
            self.activelyWritingChunk = false
        }

        // If we're not dripping the response body, there's nothing to do
        guard case .dripping(var drippingState) = self.phase else {
            return
        }

        // If we've sent all chunks, send end and be done
        if drippingState.chunksLeft < 1 {
            self.phase = .done
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            return
        }

        var dataWritten = false
        while drippingState.currentChunkBytesLeft > 0, context.channel.isWritable {
            let toSend = min(
                drippingState.currentChunkBytesLeft,
                HTTPDrippingDownloadHandler.downloadBodyChunk.readableBytes
            )
            let buffer = HTTPDrippingDownloadHandler.downloadBodyChunk.getSlice(
                at: HTTPDrippingDownloadHandler.downloadBodyChunk.readerIndex,
                length: toSend
            )!
            context.write(self.wrapOutboundOut(.body(buffer)), promise: nil)
            drippingState.currentChunkBytesLeft -= toSend
            dataWritten = true
        }

        // If we weren't able to send the full chunk, it's because the channel isn't writable. We yield until it is
        if drippingState.currentChunkBytesLeft > 0 {
            self.pendingWrite = true
            self.phase = .dripping(drippingState)
            if dataWritten {
                context.flush()
            }
            return
        }

        // We sent the full chunk. If we have no more chunks to write, we're done!
        drippingState.chunksLeft -= 1
        if drippingState.chunksLeft == 0 {
            self.phase = .done
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            return
        }

        if dataWritten {
            context.flush()
        }

        // More chunks to write.. Kick off timer
        drippingState.currentChunkBytesLeft = self.size
        self.phase = .dripping(drippingState)
        if self.scheduledCallbackHandler == nil {
            let this = NIOLoopBound(self, eventLoop: context.eventLoop)
            let loopBoundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
            self.scheduledCallbackHandler = HTTPDrippingDownloadHandlerScheduledCallbackHandler(
                handler: this,
                context: loopBoundContext
            )
        }
        // SAFTEY: scheduling the callback only potentially throws when invoked off eventloop
        do {
            try context.eventLoop.scheduleCallback(in: self.frequency, handler: self.scheduledCallbackHandler!)
        } catch {
            context.fireErrorCaught(error)
        }
    }

    private struct HTTPDrippingDownloadHandlerScheduledCallbackHandler: NIOScheduledCallbackHandler & Sendable {
        var handler: NIOLoopBound<HTTPDrippingDownloadHandler>
        var context: NIOLoopBound<ChannelHandlerContext>

        func handleScheduledCallback(eventLoop: some EventLoop) {
            self.handler.value.writeChunk(context: self.context.value)
        }
    }
}

@available(*, unavailable)
extension HTTPDrippingDownloadHandler: Sendable {}
