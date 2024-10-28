//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CNIOExtrasZlib
import NIOCore
import NIOHTTP1

extension StringProtocol {
    /// Test if this string starts with the same unicode scalars as the given string, `prefix`.
    ///
    /// - note: This will be faster than `String.startsWith` as no unicode normalisations are performed.
    ///
    /// - parameters:
    ///    - prefix: The string to match at the beginning of `self`
    /// - returns: Whether or not `self` starts with the same unicode scalars as `prefix`.
    func startsWithExactly<S: StringProtocol>(_ prefix: S) -> Bool {
        self.utf8.starts(with: prefix.utf8)
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

/// A ``HTTPResponseCompressor`` is a duplex channel handler that handles automatic streaming compression of
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
///
/// The compressor optionally accepts a predicate to help it determine on a per-request basis if compression
/// should be used, even if the client requests it for the request. This could be used to conditionally and statelessly
/// enable compression based on resource types, or by emitting and checking for marker headers as needed.
/// Since the predicate is always called, it can also be used to clean up those marker headers if compression was
/// not actually supported for any reason (ie. the client didn't provide compatible `Accept` headers, or the
/// response was missing a body due to a special status code being used)
public final class HTTPResponseCompressor: ChannelDuplexHandler, RemovableChannelHandler {
    /// This class accepts `HTTPServerRequestPart` inbound
    public typealias InboundIn = HTTPServerRequestPart
    /// This class emits `HTTPServerRequestPart` inbound.
    public typealias InboundOut = HTTPServerRequestPart
    /// This class accepts `HTTPServerResponsePart` outbound,
    public typealias OutboundIn = HTTPServerResponsePart
    /// This class emits `HTTPServerResponsePart` outbound.
    public typealias OutboundOut = HTTPServerResponsePart

    /// A closure that accepts a response header, optionally modifies it, and returns `true` if the response it belongs to should be compressed.
    ///
    /// - Parameter responseHeaders: The headers that will be used for the response. These can be modified as needed at this stage, to clean up any marker headers used to statelessly determine if compression should occur, and the new headers will be used when writing the response. Compression headers are not yet provided and should not be set; ``HTTPResponseCompressor`` will set them accordingly based on the result of this predicate.
    /// - Parameter isCompressionSupported: Set to `true` if the client requested compatible compression, and if the HTTP response supports it, otherwise `false`.
    /// - Returns: Return ``CompressionIntent/compressIfPossible`` if the compressor should proceed to compress the response, or ``CompressionIntent/doNotCompress`` if the response should not be compressed.
    ///
    /// - Note: Returning ``CompressionIntent/compressIfPossible`` is only a suggestion — when compression is not supported, the response will be returned as is along with any modified headers.
    public typealias ResponseCompressionPredicate = (
        _ responseHeaders: inout HTTPResponseHead,
        _ isCompressionSupported: Bool
    ) -> CompressionIntent

    /// A signal a ``ResponseCompressionPredicate`` returns to indicate if it intends for compression to be used or not when supported by HTTP.
    public struct CompressionIntent: Sendable, Hashable {
        /// The internal type ``CompressionIntent`` uses.
        enum RawValue {
            /// The response should be compressed if supported by the HTTP protocol.
            case compressIfPossible
            /// The response should not be compressed even if supported by the HTTP protocol.
            case doNotCompress
        }

        /// The raw value of the intent.
        let rawValue: RawValue

        /// Initialize the raw value with an internal intent.
        init(_ rawValue: RawValue) {
            self.rawValue = rawValue
        }

        /// The response should be compressed if supported by the HTTP protocol.
        public static let compressIfPossible = CompressionIntent(.compressIfPossible)
        /// The response should not be compressed even if supported by the HTTP protocol.
        public static let doNotCompress = CompressionIntent(.doNotCompress)
    }

    /// Errors which can occur when compressing
    public enum CompressionError: Error {
        // Writes were still pending when shutdown.
        case uncompressedWritesPending
        /// Data was somehow lost without being written.
        case noDataToWrite
    }

    private var compressor: NIOCompression.Compressor

    // A queue of accept headers.
    private var acceptQueue = CircularBuffer<[Substring]>(initialCapacity: 8)

    private var pendingResponse: PartialHTTPResponse!
    private var pendingWritePromise: EventLoopPromise<Void>!

    private let initialByteBufferCapacity: Int
    private let responseCompressionPredicate: ResponseCompressionPredicate?

    /// Initialize a ``HTTPResponseCompressor``.
    /// - Parameter initialByteBufferCapacity: Initial size of buffer to allocate when hander is first added.
    public convenience init(initialByteBufferCapacity: Int = 1024) {
        // TODO: This version is kept around for backwards compatibility and should be merged with the signature below in the next major version: https://github.com/apple/swift-nio-extras/issues/226
        self.init(initialByteBufferCapacity: initialByteBufferCapacity, responseCompressionPredicate: nil)
    }

    /// Initialize a ``HTTPResponseCompressor``.
    /// - Parameter initialByteBufferCapacity: Initial size of buffer to allocate when hander is first added.
    /// - Parameter responseCompressionPredicate: The predicate used to determine if the response should be compressed or not based on its headers. Defaults to `nil`, which will compress every response this handler sees. This predicate is always called whether the client supports compression for this response or not, so it can be used to clean up any marker headers you may use to determine if compression should be performed or not. Please see ``ResponseCompressionPredicate`` for more details.
    public init(
        initialByteBufferCapacity: Int = 1024,
        responseCompressionPredicate: ResponseCompressionPredicate? = nil
    ) {
        self.initialByteBufferCapacity = initialByteBufferCapacity
        self.responseCompressionPredicate = responseCompressionPredicate
        self.compressor = NIOCompression.Compressor()
    }

    /// Setup and add to the pipeline.
    /// - Parameter context: Calling context.
    public func handlerAdded(context: ChannelHandlerContext) {
        pendingResponse = PartialHTTPResponse(
            bodyBuffer: context.channel.allocator.buffer(capacity: initialByteBufferCapacity)
        )
        pendingWritePromise = context.eventLoop.makePromise()
    }

    /// Remove channel handler from the pipeline.
    /// - Parameter context: Calling context
    public func handlerRemoved(context: ChannelHandlerContext) {
        pendingWritePromise?.fail(CompressionError.uncompressedWritesPending)
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
            /// Grab the algorithm to use from the bottom of the accept queue, which will help determine if we support compression for this response or not.
            let algorithm = compressionAlgorithm()
            let requestSupportsCompression = algorithm != nil && responseHead.status.mayHaveResponseBody

            /// If a predicate was set, ask it if we should compress when compression is supported, and give the predicate a chance to clean up any marker headers that may have been set even if compression were not supported.
            let predicateCompressionIntent =
                responseCompressionPredicate?(&responseHead, requestSupportsCompression) ?? .compressIfPossible

            /// Make sure that compression should proceed, otherwise stop here and supply the response headers before configuring the compressor.
            guard let algorithm, requestSupportsCompression, predicateCompressionIntent == .compressIfPossible else {
                context.write(wrapOutboundOut(.head(responseHead)), promise: promise)
                return
            }

            /// Previous handlers in the pipeline might have already set this header even though they should not have as it is compressor responsibility to decide what encoding to use.
            responseHead.headers.replaceOrAdd(name: "Content-Encoding", value: algorithm.description)

            /// Initialize the compressor and write the header data, which marks the compressor as "active" allowing the `.body` and `.end` cases to properly compress the response rather than passing it as is.
            compressor.initialize(encoding: algorithm)
            pendingResponse.bufferResponseHead(responseHead)
            pendingWritePromise.futureResult.cascade(to: promise)
        case .body(let body):
            /// We already determined if compression should occur based on the `.head` case above, so here we simply need to check if the compressor is active or not to determine if we should compress the body chunks or stream them as is.
            if compressor.isActive {
                pendingResponse.bufferBodyPart(body)
                pendingWritePromise.futureResult.cascade(to: promise)
            } else {
                context.write(data, promise: promise)
            }
        case .end:
            guard compressor.isActive else {
                context.write(data, promise: promise)
                return
            }

            /// Compress any trailers and finalize the response. Note that this compression stage is not done in `flush()` because we need to clean up the compressor state to be ready for the next response that can come in on the same handler.
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
    private func compressionAlgorithm() -> NIOCompression.Algorithm? {
        let acceptHeaders = acceptQueue.removeFirst()

        var gzipQValue: Float = -1
        var deflateQValue: Float = -1
        var anyQValue: Float = -1

        for acceptHeader in acceptHeaders {
            if acceptHeader.startsWithExactly("gzip") || acceptHeader.startsWithExactly("x-gzip") {
                gzipQValue = qValueFromHeader(acceptHeader)
            } else if acceptHeader.startsWithExactly("deflate") {
                deflateQValue = qValueFromHeader(acceptHeader)
            } else if acceptHeader.startsWithExactly("*") {
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
            stillPendingPromise.fail(CompressionError.noDataToWrite)
        }

        // Reset the pending promise.
        pendingWritePromise = context.eventLoop.makePromise()
    }
}

@available(*, unavailable)
extension HTTPResponseCompressor: Sendable {}

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
        head != nil && end != nil
    }

    var mustFlush: Bool {
        end != nil
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
    mutating func flush(
        compressor: inout NIOCompression.Compressor,
        allocator: ByteBufferAllocator
    ) -> (HTTPResponseHead?, ByteBuffer?, HTTPServerResponsePart?) {
        var outputBody: ByteBuffer? = nil
        if self.body.readableBytes > 0 || mustFlush {
            let compressedBody = compressor.compress(inputBuffer: &self.body, allocator: allocator, finalise: mustFlush)
            if isCompleteResponse {
                head!.headers.remove(name: "transfer-encoding")
                head!.headers.replaceOrAdd(name: "content-length", value: "\(compressedBody.readableBytes)")
            } else if head != nil && head!.status.mayHaveResponseBody {
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
