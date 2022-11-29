//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2022 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOHTTP1

public final class HTTP1ProxyConnectHandler: ChannelDuplexHandler, RemovableChannelHandler {
    public typealias OutboundIn = Never
    public typealias OutboundOut = HTTPClientRequestPart
    public typealias InboundIn = HTTPClientResponsePart

    enum State {
        // transitions to `.connectSent` or `.failed`
        case initialized
        // transitions to `.headReceived` or `.failed`
        case connectSent(Scheduled<Void>)
        // transitions to `.completed` or `.failed`
        case headReceived(Scheduled<Void>)
        // final error state
        case failed(Error)
        // final success state
        case completed
    }

    private var state: State = .initialized

    private let targetHost: String
    private let targetPort: Int
    private let headers: HTTPHeaders
    private let deadline: NIODeadline

    private var proxyEstablishedPromise: EventLoopPromise<Void>?
    var proxyEstablishedFuture: EventLoopFuture<Void>? {
        return self.proxyEstablishedPromise?.futureResult
    }

    init(targetHost: String,
         targetPort: Int,
         headers: HTTPHeaders,
         deadline: NIODeadline) {
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.headers = headers
        self.deadline = deadline
    }

    public func handlerAdded(context: ChannelHandlerContext) {
        self.proxyEstablishedPromise = context.eventLoop.makePromise(of: Void.self)

        self.sendConnect(context: context)
    }

    public func handlerRemoved(context: ChannelHandlerContext) {
        switch self.state {
        case .failed, .completed:
            break
        case .initialized, .connectSent, .headReceived:
            self.state = .failed(Error.noResult)
            self.proxyEstablishedPromise?.fail(Error.noResult)
        }
    }

    public func channelActive(context: ChannelHandlerContext) {
        self.sendConnect(context: context)
    }

    public func channelInactive(context: ChannelHandlerContext) {
        switch self.state {
        case .initialized:
            preconditionFailure("How can we receive a channelInactive before a channelActive?")
        case .connectSent(let timeout), .headReceived(let timeout):
            timeout.cancel()
            self.failWithError(Error.remoteConnectionClosed, context: context, closeConnection: false)

        case .failed, .completed:
            break
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        preconditionFailure("We don't support outgoing traffic during HTTP Proxy update.")
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.unwrapInboundIn(data) {
        case .head(let head):
            self.handleHTTPHeadReceived(head, context: context)
        case .body:
            self.handleHTTPBodyReceived(context: context)
        case .end:
            self.handleHTTPEndReceived(context: context)
        }
    }

    private func sendConnect(context: ChannelHandlerContext) {
        guard case .initialized = self.state else {
            // we might run into this handler twice, once in handlerAdded and once in channelActive.
            return
        }

        let timeout = context.eventLoop.scheduleTask(deadline: self.deadline) {
            switch self.state {
            case .initialized:
                preconditionFailure("How can we have a scheduled timeout, if the connection is not even up?")

            case .connectSent, .headReceived:
                self.failWithError(Error.httpProxyHandshakeTimeout, context: context)

            case .failed, .completed:
                break
            }
        }

        self.state = .connectSent(timeout)

        let head = HTTPRequestHead(
            version: .init(major: 1, minor: 1),
            method: .CONNECT,
            uri: "\(self.targetHost):\(self.targetPort)",
            headers: self.headers
        )

        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
        context.flush()
    }

    private func handleHTTPHeadReceived(_ head: HTTPResponseHead, context: ChannelHandlerContext) {
        guard case .connectSent(let scheduled) = self.state else {
            preconditionFailure("HTTPDecoder should throw an error, if we have not send a request")
        }

        switch head.status.code {
        case 200..<300:
            // Any 2xx (Successful) response indicates that the sender (and all
            // inbound proxies) will switch to tunnel mode immediately after the
            // blank line that concludes the successful response's header section
            self.state = .headReceived(scheduled)
        case 407:
            self.failWithError(Error.proxyAuthenticationRequired, context: context)

        default:
            // Any response other than a successful response indicates that the tunnel
            // has not yet been formed and that the connection remains governed by HTTP.
            self.failWithError(Error.invalidProxyResponse, context: context)
        }
    }

    private func handleHTTPBodyReceived(context: ChannelHandlerContext) {
        switch self.state {
        case .headReceived(let timeout):
            timeout.cancel()
            // we don't expect a body
            self.failWithError(Error.invalidProxyResponse, context: context)
        case .failed:
            // ran into an error before... ignore this one
            break
        case .completed, .connectSent, .initialized:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    private func handleHTTPEndReceived(context: ChannelHandlerContext) {
        switch self.state {
        case .headReceived(let timeout):
            timeout.cancel()
            self.state = .completed
            self.proxyEstablishedPromise?.succeed(())

        case .failed:
            // ran into an error before... ignore this one
            break
        case .initialized, .connectSent, .completed:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    private func failWithError(_ error: Error, context: ChannelHandlerContext, closeConnection: Bool = true) {
        self.state = .failed(error)
        self.proxyEstablishedPromise?.fail(error)
        context.fireErrorCaught(error)
        if closeConnection {
            context.close(mode: .all, promise: nil)
        }
    }

    /// Error types for ``HTTP1ProxyConnectHandler``
    public struct Error: Swift.Error, CustomStringConvertible, Equatable {
        fileprivate enum ErrorEnum: String {
            case proxyAuthenticationRequired
            case invalidProxyResponse
            case remoteConnectionClosed
            case httpProxyHandshakeTimeout
            case noResult
        }
        fileprivate let error: ErrorEnum

        /// return as String
        public var description: String { return error.rawValue }

        /// Proxy response status `407` indicates that authentication is required
        public static let proxyAuthenticationRequired = Error(error: .proxyAuthenticationRequired)

        /// Proxy response contains unexpected status or body
        public static let invalidProxyResponse = Error(error: .invalidProxyResponse)

        /// Connection has been closed for ongoing request
        public static let remoteConnectionClosed = Error(error: .remoteConnectionClosed)

        /// Proxy connection handshake has timed out
        public static let httpProxyHandshakeTimeout = Error(error: .httpProxyHandshakeTimeout)

        /// Handler was removed before we received a result for the request
        public static let noResult = Error(error: .noResult)
    }}
