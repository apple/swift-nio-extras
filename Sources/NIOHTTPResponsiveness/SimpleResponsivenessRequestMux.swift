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

import Algorithms
import HTTPTypes
import NIOCore
import NIOHTTPTypes

/// A basic request multiplexer that identifies which request type (config, download, upload) is requested and adds the
/// appropriate handler. Once the handler has been added, all data is passed through to the newly added handler.
///
/// The multiplexer handles the following requests:
/// - GET `/responsiveness`: Returns the configuration buffer
/// - GET `/responsiveness/download/{size}`: Adds a handler for downloading data of the specified size
/// - POST `/responsiveness/upload`: Adds a handler for uploading data
/// - GET `/drip`: Adds a handler for responds with a configurable stream of zeroes
///
/// Per default other requests get a 404 response. Can be configured to accept other requests as well and forward them
/// along the channel pipeline.
public final class SimpleResponsivenessRequestMux: ChannelInboundHandler {

    public typealias InboundIn = HTTPRequestPart
    public typealias OutboundOut = HTTPResponsePart

    // Predefine some common things we'll need in responses
    private static let notFoundBody = ByteBuffer(string: "Not Found")

    // Config returned to user that lists responsiveness endpoints
    private let responsivenessConfigBuffer: ByteBuffer

    // Whether or not to foward other requests down the channel pipeline
    private var forwardOtherRequests: Bool

    /// Initializes a new `SimpleResponsivenessRequestMux` with the provided configuration buffer.
    ///
    /// This initializer creates a request multiplexer that will return the provided configuration
    /// buffer when the `/responsiveness` endpoint is accessed. All requests that don't match
    /// the defined responsiveness endpoints will be rejected with a 404 Not Found response.
    ///
    /// - Parameter responsivenessConfigBuffer: A `ByteBuffer` containing the configuration information
    ///   to be returned when the `/responsiveness` endpoint is accessed.
    public init(responsivenessConfigBuffer: ByteBuffer) {
        self.responsivenessConfigBuffer = responsivenessConfigBuffer
        self.forwardOtherRequests = false
    }

    /// Initializes a new `SimpleResponsivenessRequestMux` with the provided configuration buffer
    /// and request handling behavior.
    ///
    /// This initializer creates a request multiplexer that will return the provided configuration
    /// buffer when the `/responsiveness` endpoint is accessed. The behavior for requests that don't
    /// match the defined responsiveness endpoints is determined by the `forwardOtherRequests` parameter.
    ///
    /// - Parameters:
    ///   - responsivenessConfigBuffer: A `ByteBuffer` containing the configuration information
    ///     to be returned when the `/responsiveness` endpoint is accessed.
    ///   - forwardOtherRequests: If `false`, requests that don't match the defined responsiveness
    ///     endpoints will be rejected with a 404 Not Found response. If `true`, such requests
    ///     will be passed down the channel pipeline for other handlers to process.
    public init(responsivenessConfigBuffer: ByteBuffer, forwardOtherRequests: Bool) {
        self.responsivenessConfigBuffer = responsivenessConfigBuffer
        self.forwardOtherRequests = forwardOtherRequests
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        do {
            if case let .head(request) = self.unwrapInboundIn(data) {
                // TODO: get rid of this altogether and instead create an empty iterator below
                guard let path = request.path else {
                    self.writeSimpleResponse(
                        context: context,
                        status: .notFound,
                        body: SimpleResponsivenessRequestMux.notFoundBody
                    )
                    return
                }

                var pathComponents = path.utf8.lazy.split(separator: UInt8(ascii: "?"), maxSplits: 1).makeIterator()
                let firstPathComponent = pathComponents.next()!
                let queryArgsString = pathComponents.next()

                // Split the path into components
                var uriComponentIterator = firstPathComponent.split(
                    separator: UInt8(ascii: "/"),
                    maxSplits: 3,
                    omittingEmptySubsequences: false
                ).lazy.map(Substring.init).makeIterator()

                // Handle possible path components
                switch (
                    request.method, uriComponentIterator.next(), uriComponentIterator.next(),
                    uriComponentIterator.next(), uriComponentIterator.next().flatMap { Int($0) }
                ) {
                case (.get, .some(""), .some("responsiveness"), .none, .none):
                    self.writeSimpleResponse(
                        context: context,
                        status: .ok,
                        body: self.responsivenessConfigBuffer
                    )
                case (.get, .some(""), .some("responsiveness"), .some("download"), .some(let size)):
                    try context.pipeline.syncOperations.addHandler(
                        HTTPDrippingDownloadHandler(count: 1, size: size),
                        position: .after(self)
                    )
                case (.post, .some(""), .some("responsiveness"), .some("upload"), .none):
                    // Check if we should expect a certain count
                    var expectation: Int?
                    if let lengthHeaderValue = request.headerFields[.contentLength] {
                        if let expectedLength = Int(lengthHeaderValue) {
                            expectation = expectedLength
                        }
                    }
                    try context.pipeline.syncOperations.addHandler(
                        HTTPReceiveDiscardHandler(expectation: expectation),
                        position: .after(self)
                    )
                case (_, .some(""), .some("drip"), .none, .none):
                    if let queryArgsString = queryArgsString {
                        guard let handler = HTTPDrippingDownloadHandler(queryArgsString: queryArgsString) else {
                            self.writeSimpleResponse(context: context, status: .badRequest, body: .init())
                            return
                        }
                        try context.pipeline.syncOperations.addHandler(handler, position: .after(self))
                    } else {
                        try context.pipeline.syncOperations.addHandler(
                            HTTPDrippingDownloadHandler(),
                            position: .after(self)
                        )
                    }
                default:
                    if !self.forwardOtherRequests {
                        self.writeSimpleResponse(
                            context: context,
                            status: .notFound,
                            body: SimpleResponsivenessRequestMux.notFoundBody
                        )
                        return
                    }
                }
            }

            context.fireChannelRead(data)
        } catch {
            self.writeSimpleResponse(
                context: context,
                status: .internalServerError,
                body: ByteBuffer.init()
            )
        }
    }

    private func writeSimpleResponse(
        context: ChannelHandlerContext,
        status: HTTPResponse.Status,
        body: ByteBuffer
    ) {
        let bodyLen = body.readableBytes
        let responseHead = HTTPResponse(
            status: status,
            headerFields: HTTPFields(dictionaryLiteral: (.contentLength, "\(bodyLen)"))
        )
        context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        context.write(self.wrapOutboundOut(.body(body)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }
}

@available(*, unavailable)
extension SimpleResponsivenessRequestMux: Sendable {}
