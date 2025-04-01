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

/// HTTP request handler that receives arbitrary bytes and discards them
public final class HTTPReceiveDiscardHandler: ChannelInboundHandler {

    public typealias InboundIn = HTTPRequestPart
    public typealias OutboundOut = HTTPResponsePart

    private let expectation: Int?
    private var expectationViolated = false
    private var received = 0

    /// Initializes `HTTPReceiveDiscardHandler`
    /// - Parameter expectation: how many bytes should be expected. If more
    ///             bytes are received than expected, an error status code will
    ///             be sent to the client
    public init(expectation: Int?) {
        self.expectation = expectation
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = self.unwrapInboundIn(data)

        switch part {
        case .head:
            return
        case .body(let buffer):
            self.received += buffer.readableBytes

            // If the expectation is violated, send 4xx
            if let expectation = self.expectation, self.received > expectation {
                self.onExpectationViolated(context: context, expectation: expectation)
            }
        case .end:
            if self.expectationViolated {
                // Already flushed a response, nothing else to do
                return
            }

            if let expectation = self.expectation, self.received != expectation {
                self.onExpectationViolated(context: context, expectation: expectation)
                return
            }

            let responseBody = ByteBuffer(string: "Received \(self.received) bytes")
            self.writeSimpleResponse(context: context, status: .ok, body: responseBody)
        }
    }

    private func onExpectationViolated(context: ChannelHandlerContext, expectation: Int) {
        self.expectationViolated = true

        let body = ByteBuffer(
            string:
                "Received in excess of expectation; expected(\(expectation)) received(\(self.received))"
        )
        self.writeSimpleResponse(context: context, status: .badRequest, body: body)
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
extension HTTPReceiveDiscardHandler: Sendable {}
