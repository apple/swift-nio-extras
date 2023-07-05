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

import HTTPTypes
import NIOCore

/// The parts of a complete HTTP message, either request or response.
///
/// An HTTP message is made up of a request, or one or more response headers,
/// encoded by `.head`, zero or more body parts, and optionally some trailers. To
/// indicate that a complete HTTP message has been sent or received, we use `.end`,
/// which may also contain any trailers that make up the message.
public enum HTTPTypePart<HeadT: Equatable, BodyT: Equatable> {
    case head(HeadT)
    case body(BodyT)
    case end(HTTPFields?)
}

extension HTTPTypePart: Sendable where HeadT: Sendable, BodyT: Sendable {}

extension HTTPTypePart: Equatable {}

/// The components of an HTTP request from the view of an HTTP client.
public typealias HTTPTypeClientRequestPart = HTTPTypePart<HTTPRequest, IOData>

/// The components of an HTTP request from the view of an HTTP server.
public typealias HTTPTypeServerRequestPart = HTTPTypePart<HTTPRequest, ByteBuffer>

/// The components of an HTTP response from the view of an HTTP client.
public typealias HTTPTypeClientResponsePart = HTTPTypePart<HTTPResponse, ByteBuffer>

/// The components of an HTTP response from the view of an HTTP server.
public typealias HTTPTypeServerResponsePart = HTTPTypePart<HTTPResponse, IOData>
