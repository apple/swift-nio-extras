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

/// Basic request multiplexer that identifies which request type (config, download, upload) is requested and adds the appropriate handler.
/// Once the handler has been added, all data is passed through to the newly added handler.
public final class SimpleResponsivenessRequestMux: ChannelInboundHandler {

    public typealias InboundIn = HTTPRequestPart
    public typealias OutboundOut = HTTPResponsePart

    // Predefine some common things we'll need in responses
    private static let notFoundBody = ByteBuffer(string: "Not Found")

    // Whether or not we added a handler after us
    private var handlerAdded = false

    // Config returned to user that lists responsiveness endpoints
    private let responsivenessConfigBuffer: ByteBuffer

    public init(responsivenessConfigBuffer: ByteBuffer) {
        self.responsivenessConfigBuffer = responsivenessConfigBuffer
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
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

            var pathComponents = path.utf8.split(separator: "?".utf8, maxSplits: 1).makeIterator()
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
                self.addHandlerOrInternalError(context: context, handler: HTTPDrippingDownloadHandler(count: 1, size: size))
            case (.post, .some(""), .some("responsiveness"), .some("upload"), .none):
                // Check if we should expect a certain count
                var expectation: Int?
                if let lengthHeaderValue = request.headerFields[.contentLength] {
                    if let expectedLength = Int(lengthHeaderValue) {
                        expectation = expectedLength
                    }
                }
                self.addHandlerOrInternalError(context: context, handler: HTTPReceiveDiscardHandler(expectation: expectation))
            case (_, .some(""), .some("drip"), .none, .none):
                if let queryArgsString = queryArgsString {
                    guard let handler = HTTPDrippingDownloadHandler(queryArgsString: queryArgsString) else {
                        self.writeSimpleResponse(context: context, status: .badRequest, body: .init())
                        return
                    }
                    self.addHandlerOrInternalError(context: context, handler: handler)
                } else {
                    self.addHandlerOrInternalError(context: context, handler: HTTPDrippingDownloadHandler())
                }
            default:
                self.writeSimpleResponse(
                    context: context,
                    status: .notFound,
                    body: SimpleResponsivenessRequestMux.notFoundBody
                )
            }
        }

        // Only pass through data through if we've actually added a handler. If we didn't add a handler, it's because we
        // directly responded. In this case, we don't care about the rest of the request.
        if self.handlerAdded {
            context.fireChannelRead(data)
        }
    }

    /// Adding handlers is fallible. If we fail to do it, we should return 500 to the user
    private func addHandlerOrInternalError(context: ChannelHandlerContext, handler: ChannelHandler) {
        do {
            try context.pipeline.syncOperations.addHandler(
                handler,
                position: ChannelPipeline.Position.after(self)
            )
            self.handlerAdded = true
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
