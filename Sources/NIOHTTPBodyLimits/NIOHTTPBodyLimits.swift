//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2026 Apple Inc. and the SwiftNIO project authors
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

/// Describes how the `NIOHTTPRequestBodySizeLimitHandler` should react when an
/// incoming HTTP request body exceeds the configured size limit.
public enum NIOHTTPBodyLimitOverflowAction: Sendable, Hashable {
    /// Respond to the client with an HTTP status code (413 Content Too Large is
    /// the recommended status), then close the connection.
    ///
    /// This is the default and recommended action for HTTP/1.1 servers: the
    /// offending request is answered immediately and the client is not left
    /// guessing. The remaining bytes of the oversized request body are discarded,
    /// so no memory is spent buffering them.
    case respond(status: HTTPResponse.Status)

    /// Fire `NIOHTTPBodyLimitOverflowError` with `fireErrorCaught` and close the
    /// connection, leaving the response to the server application. Use this action
    /// when your application owns the error handling (e.g., custom logging,
    /// metrics, or HTTP/2 `RST_STREAM` handling).
    case fail
}

/// An error fired when an incoming HTTP request body exceeds the configured
/// size limit, used when ``NIOHTTPBodyLimitOverflowAction/fail`` is configured.
public struct NIOHTTPBodyLimitOverflowError: Error, Hashable, Sendable {
    /// The HTTP method of the offending request.
    public let method: HTTPRequest.Method
    /// The path of the offending request.
    public let path: String
    /// The configured size limit, in bytes.
    public let limit: Int
    /// The number of bytes received (or declared) at the point the limit was
    /// exceeded. For a `Content-Length` violation this is the declared length.
    public let received: Int

    public init(method: HTTPRequest.Method, path: String, limit: Int, received: Int) {
        self.method = method
        self.path = path
        self.limit = limit
        self.received = received
    }
}
