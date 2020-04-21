//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
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

extension StringProtocol {
    /// Test if this `Collection` starts with the unicode scalars of `needle`.
    ///
    /// - note: This will be faster than `String.startsWith` as no unicode normalisations are performed.
    ///
    /// - parameters:
    ///    - needle: The `Collection` of `Unicode.Scalar`s to match at the beginning of `self`
    /// - returns: If `self` started with the elements contained in `needle`.
    func startsWithSameUnicodeScalars<S: StringProtocol>(string needle: S) -> Bool {
        return self.unicodeScalars.starts(with: needle.unicodeScalars)
    }
}


/// Given a header value, extracts the q value if there is one present. If one is not present,
/// returns the default q value, 1.0.
private func qValueFromHeader<S: StringProtocol>(_ text: S) -> Float {
    let headerParts = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
    guard headerParts.count > 1 && headerParts[1].count > 0 else {
        return 1
    }

    // We have a Q value.
    let qValue = Float(headerParts[1].split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[1]) ?? 0
    if qValue < 0 || qValue > 1 || qValue.isNaN {
        return 0
    }
    return qValue
}

/// A HTTPResponseCompressor is a duplex channel handler that handles automatic streaming compression of
/// HTTP responses. It respects the client's Accept-Encoding preferences, including q-values if present,
/// and ensures that clients are served the compression algorithm that works best for them.
///
/// This compressor supports gzip and deflate. It works best if many writes are made between flushes.
///
/// Note that this compressor performs the compression on the event loop thread. This means that compressing
/// some resources, particularly those that do not benefit from compression or that could have been compressed
/// ahead-of-time instead of dynamically, could be a waste of CPU time and latency for relatively minimal
/// benefit. This channel handler should be present in the pipeline only for dynamically-generated and
/// highly-compressible content, which will see the biggest benefits from streaming compression.
public final class HTTPResponseCompressor: ChannelDuplexHandler, RemovableChannelHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias InboundOut = HTTPServerRequestPart
    public typealias OutboundIn = HTTPServerResponsePart
    public typealias OutboundOut = HTTPServerResponsePart

    private var compressor: HTTPCompression.Compressor
    private var algorithm: HTTPCompression.CompressionAlgorithm?

    // A queue of accept headers.
    private var acceptQueue = CircularBuffer<[Substring]>(initialCapacity: 8)

    private var pendingResponse: PartialHTTPResponse!
    private var pendingWritePromise: EventLoopPromise<Void>!

    private let initialByteBufferCapacity: Int

    public init(initialByteBufferCapacity: Int = 1024) {
        self.initialByteBufferCapacity = initialByteBufferCapacity
        self.compressor = HTTPCompression.Compressor()
    }

    public func handlerAdded(context: ChannelHandlerContext) {
        pendingResponse = PartialHTTPResponse(bodyBuffer: context.channel.allocator.buffer(capacity: initialByteBufferCapacity))
        pendingWritePromise = context.eventLoop.makePromise()
    }

    public func handlerRemoved(context: ChannelHandlerContext) {
        pendingWritePromise?.fail(HTTPCompression.CompressionError.uncompressedWritesPending)
        compressor.shutdownIfActive()
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case .head(let requestHead) = unwrapInboundIn(data) {
            acceptQueue.append(requestHead.headers[canonicalForm: "accept-encoding"])
        }

        context.fireChannelRead(data)
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let httpData = unwrapOutboundIn(data)
        switch httpData {
        case .head(var responseHead):
            guard let algorithm = compressionAlgorithm() else {
                context.write(wrapOutboundOut(.head(responseHead)), promise: promise)
                return
            }
            // Previous handlers in the pipeline might have already set this header even though
            // they should not as it is compressor responsibility to decide what encoding to use
            responseHead.headers.replaceOrAdd(name: "Content-Encoding", value: algorithm.rawValue)
            compressor.initialize(encoding: algorithm)
            pendingResponse.bufferResponseHead(responseHead)
            pendingWritePromise.futureResult.cascade(to: promise)
        case .body(let body):
            if compressor.isActive {
                pendingResponse.bufferBodyPart(body)
                pendingWritePromise.futureResult.cascade(to: promise)
            } else {
                context.write(data, promise: promise)
            }
        case .end:
            // This compress is not done in flush because we need to be done with the
            // compressor now.
            guard compressor.isActive else {
                context.write(data, promise: promise)
                return
            }

            pendingResponse.bufferResponseEnd(httpData)
            pendingWritePromise.futureResult.cascade(to: promise)
            emitPendingWrites(context: context)
            compressor.shutdown()
        }
    }

    public func flush(context: ChannelHandlerContext) {
        emitPendingWrites(context: context)
        context.flush()
    }

    /// Determines the compression algorithm to use for the next response.
    ///
    /// Returns the compression algorithm to use, or nil if the next response
    /// should not be compressed.
    private func compressionAlgorithm() -> HTTPCompression.CompressionAlgorithm? {
        let acceptHeaders = acceptQueue.removeFirst()

        var gzipQValue: Float = -1
        var deflateQValue: Float = -1
        var anyQValue: Float = -1

        for acceptHeader in acceptHeaders {
            if acceptHeader.startsWithSameUnicodeScalars(string: "gzip") || acceptHeader.startsWithSameUnicodeScalars(string: "x-gzip") {
                gzipQValue = qValueFromHeader(acceptHeader)
            } else if acceptHeader.startsWithSameUnicodeScalars(string: "deflate") {
                deflateQValue = qValueFromHeader(acceptHeader)
            } else if acceptHeader.startsWithSameUnicodeScalars(string: "*") {
                anyQValue = qValueFromHeader(acceptHeader)
            }
        }

        if gzipQValue > 0 || deflateQValue > 0 {
            return gzipQValue > deflateQValue ? .gzip : .deflate
        } else if anyQValue > 0 {
            // Though gzip is usually less well compressed than deflate, it has slightly
            // wider support because it's unabiguous. We therefore default to that unless
            // the client has expressed a preference.
            return .gzip
        }

        return nil
    }

    /// Emits all pending buffered writes to the network, optionally compressing the
    /// data. Resets the pending write buffer and promise.
    ///
    /// Called either when a HTTP end message is received or our flush() method is called.
    private func emitPendingWrites(context: ChannelHandlerContext) {
        let writesToEmit = pendingResponse.flush(compressor: &compressor, allocator: context.channel.allocator)
        var pendingPromise = pendingWritePromise

        if let writeHead = writesToEmit.0 {
            context.write(wrapOutboundOut(.head(writeHead)), promise: pendingPromise)
            pendingPromise = nil
        }

        if let writeBody = writesToEmit.1 {
            context.write(wrapOutboundOut(.body(.byteBuffer(writeBody))), promise: pendingPromise)
            pendingPromise = nil
        }

        if let writeEnd = writesToEmit.2 {
            context.write(wrapOutboundOut(writeEnd), promise: pendingPromise)
            pendingPromise = nil
        }

        // If we still have the pending promise, we never emitted a write. Fail the promise,
        // as anything that is listening for its data somehow lost it.
        if let stillPendingPromise = pendingPromise {
            stillPendingPromise.fail(HTTPCompression.CompressionError.noDataToWrite)
        }

        // Reset the pending promise.
        pendingWritePromise = context.eventLoop.makePromise()
    }
}
/// A buffer object that allows us to keep track of how much of a HTTP response we've seen before
/// a flush.
///
/// The strategy used in this module is that we want to have as much information as possible before
/// we compress, and to compress as few times as possible. This is because in the ideal situation we
/// will have a complete HTTP response to compress in one shot, allowing us to update the content
/// length, rather than force the response to be chunked. It is much easier to do the right thing
/// if we can encapsulate our ideas about how HTTP responses in an entity like this.
private struct PartialHTTPResponse {
    var head: HTTPResponseHead?
    var body: ByteBuffer
    var end: HTTPServerResponsePart?
    private let initialBufferSize: Int

    var isCompleteResponse: Bool {
        return head != nil && end != nil
    }

    var mustFlush: Bool {
        return end != nil
    }

    init(bodyBuffer: ByteBuffer) {
        body = bodyBuffer
        initialBufferSize = bodyBuffer.capacity
    }

    mutating func bufferResponseHead(_ head: HTTPResponseHead) {
        precondition(self.head == nil)
        self.head = head
    }

    mutating func bufferBodyPart(_ bodyPart: IOData) {
        switch bodyPart {
        case .byteBuffer(var buffer):
            body.writeBuffer(&buffer)
        case .fileRegion:
            fatalError("Cannot currently compress file regions")
        }
    }

    mutating func bufferResponseEnd(_ end: HTTPServerResponsePart) {
        precondition(self.end == nil)
        guard case .end = end else {
            fatalError("Buffering wrong entity type: \(end)")
        }
        self.end = end
    }

    private mutating func clear() {
        head = nil
        end = nil
        body.clear()
        body.reserveCapacity(initialBufferSize)
    }

    /*mutating private func compressBody(compressor: inout z_stream, allocator: ByteBufferAllocator, flag: Int32) -> ByteBuffer? {
        guard body.readableBytes > 0 else {
            return nil
        }

        // deflateBound() provides an upper limit on the number of bytes the input can
        // compress to. We add 5 bytes to handle the fact that Z_SYNC_FLUSH will append
        // an empty stored block that is 5 bytes long.
        let bufferSize = Int(deflateBound(&compressor, UInt(body.readableBytes)))
        var outputBuffer = allocator.buffer(capacity: bufferSize)

        // Now do the one-shot compression. All the data should have been consumed.
        compressor.oneShotDeflate(from: &body, to: &outputBuffer, flag: flag)
        precondition(body.readableBytes == 0)
        precondition(outputBuffer.readableBytes > 0)
        return outputBuffer
    }*/

    /// Flushes the buffered data into its constituent parts.
    ///
    /// Returns a three-tuple of a HTTP response head, compressed body bytes, and any end that
    /// may have been buffered. Each of these types is optional.
    ///
    /// If the head is flushed, it will have had its headers mutated based on whether we had the whole
    /// response or not. If nil, the head has previously been emitted.
    ///
    /// If the body is nil, it means no writes were buffered (that is, our buffer of bytes has no
    /// readable bytes in it). This should usually mean that no write is issued.
    ///
    /// Calling this function resets the buffer, freeing any excess memory allocated in the internal
    /// buffer and losing all copies of the other HTTP data. At this point it may freely be reused.
    mutating func flush(compressor: inout HTTPCompression.Compressor, allocator: ByteBufferAllocator) -> (HTTPResponseHead?, ByteBuffer?, HTTPServerResponsePart?) {
        var outputBody: ByteBuffer? = nil
        if self.body.readableBytes > 0 {
            let compressedBody = compressor.compress(inputBuffer: &self.body, allocator: allocator, finalise: mustFlush)
            if isCompleteResponse {
                head!.headers.remove(name: "transfer-encoding")
                head!.headers.replaceOrAdd(name: "content-length", value: "\(compressedBody.readableBytes)")
            }
            else if head != nil && head!.status.mayHaveResponseBody {
                head!.headers.remove(name: "content-length")
                head!.headers.replaceOrAdd(name: "transfer-encoding", value: "chunked")
            }
            outputBody = compressedBody
        }

        let response = (head, outputBody, end)
        clear()
        return response
    }
}

