//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CNIOExtrasZlib
import NIO
import NIOHTTP1

public final class HTTPRequestCompressor: ChannelOutboundHandler, RemovableChannelHandler {
    public typealias OutboundIn = HTTPClientRequestPart
    public typealias OutboundOut = HTTPClientRequestPart

    /// Handler state
    enum State {
        /// handler hasn't started
        case idle
        /// handler has recived a head
        case head(HTTPRequestHead)
        /// handler has received a head and a body, but hasnt written anything yet
        case body(HTTPRequestHead, ByteBuffer)
        /// handler has written the head and some of the body out.
        case partialBody(ByteBuffer)
        /// handler has finished
        case end
    }

    /// encoding algorithm to use
    var encoding: HTTPCompression.CompressionAlgorithm
    /// handler state
    var state: State
    /// compression handler
    var compressor: HTTPCompression.Compressor
    /// pending write promise
    var pendingWritePromise: EventLoopPromise<Void>!
    
    /// Initialize a NIOHTTPRequestCompressor
    /// - Parameter encoding: Compression algorithm to use
    public init(encoding: HTTPCompression.CompressionAlgorithm) {
        self.encoding = encoding
        self.state = .idle
        self.compressor = HTTPCompression.Compressor()
    }
    
    public func handlerAdded(context: ChannelHandlerContext) {
        pendingWritePromise = context.eventLoop.makePromise()
    }

    public func handlerRemoved(context: ChannelHandlerContext) {
        pendingWritePromise.fail(HTTPCompression.CompressionError.uncompressedWritesPending)
        compressor.shutdownIfActive()
    }

    /// Write to channel
    /// - Parameters:
    ///   - context: Channel handle context which this handler belongs to
    ///   - data: Data being sent through the channel
    ///   - promise: The eventloop promise that should be notified when the operation completes
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        pendingWritePromise.futureResult.cascade(to: promise)
        
        let httpData = unwrapOutboundIn(data)
        switch httpData {
        case .head(let head):
            switch state {
            case .idle:
                state = .head(head)
            default:
                preconditionFailure("Unexpected HTTP head")
            }
            compressor.initialize(encoding: self.encoding)

        case .body(let buffer):
            switch state {
            case .head(var head):
                // We only have a head, this is the first body part
                guard case .byteBuffer(let part) = buffer else { preconditionFailure("Expected a ByteBuffer") }
                // now we have a body lets add the content-encoding header
                head.headers.replaceOrAdd(name: "Content-Encoding", value: self.encoding.rawValue)
                state = .body(head, part)
            case .body(let head, var body):
                // we have a head and a body, extend the body with this body part
                guard case .byteBuffer(var part) = buffer else { preconditionFailure("Expected a ByteBuffer") }
                body.writeBuffer(&part)
                state = .body(head, body)
            case .partialBody(var body):
                // we have a partial body, extend the partial body with this body part
                guard case .byteBuffer(var part) = buffer else { preconditionFailure("Expected a ByteBuffer") }
                body.writeBuffer(&part)
                state = .partialBody(body)
            default:
                preconditionFailure("Unexpected Body")
            }
            
        case .end:
            switch state {
            case .head(let head):
                // only found a head
                context.write(wrapOutboundOut(.head(head)), promise: nil)
                context.write(data, promise: pendingWritePromise)
            case .body(var head, var body):
                // have head and the whole of the body. Compress body, set content length header and write it all out, including the end
                let outputBuffer = compressor.compress(inputBuffer: &body, allocator: context.channel.allocator, finalise: true)
                head.headers.replaceOrAdd(name: "Content-Length", value: outputBuffer.readableBytes.description)
                context.write(wrapOutboundOut(.head(head)), promise: nil)
                context.write(wrapOutboundOut(.body(.byteBuffer(outputBuffer))), promise: nil)
                context.write(data, promise: pendingWritePromise)
            case .partialBody(var body):
                // have a section of the body. Compress that section of the body and write it out along with the end
                let outputBuffer = compressor.compress(inputBuffer: &body, allocator: context.channel.allocator, finalise: true)
                context.write(wrapOutboundOut(.body(.byteBuffer(outputBuffer))), promise: nil)
                context.write(data, promise: pendingWritePromise)
            default:
                preconditionFailure("Unexpected End")
            }
            state = .end
            compressor.shutdown()
        }
    }
    
    public func flush(context: ChannelHandlerContext) {
        switch state {
        case .head(var head):
            head.headers.remove(name: "Content-Length")
            head.headers.replaceOrAdd(name: "Transfer-Encoding", value: "chunked")
            context.write(wrapOutboundOut(.head(head)), promise: pendingWritePromise)
            state = .partialBody(context.channel.allocator.buffer(capacity: 0))

        case .body(var head, var body):
            // Write out head with transfer-encoding set to "chunked" as we cannot set the content length
            // Compress and write out what we have of the the body
            let outputBuffer = compressor.compress(inputBuffer: &body, allocator: context.channel.allocator, finalise: false)
            head.headers.remove(name: "Content-Length")
            head.headers.replaceOrAdd(name: "Transfer-Encoding", value: "chunked")
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(outputBuffer))), promise: pendingWritePromise)
            state = .partialBody(context.channel.allocator.buffer(capacity: 0))
            
        case .partialBody(var body):
            // Compress and write out what we have of the body
            let outputBuffer = compressor.compress(inputBuffer: &body, allocator: context.channel.allocator, finalise: false)
            context.write(wrapOutboundOut(.body(.byteBuffer(outputBuffer))), promise: pendingWritePromise)
            state = .partialBody(context.channel.allocator.buffer(capacity: 0))
            
        default:
            context.flush()
            return
        }
        // reset pending write promise
        pendingWritePromise = context.eventLoop.makePromise()
        context.flush()
    }
}

