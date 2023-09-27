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

/// The parts of a complete HTTP request.
///
/// An HTTP request message is made up of a request encoded by `.head`, zero or
/// more body parts, and optionally some trailers.
///
/// To indicate that a complete HTTP message has been sent or received, we use
/// `.end`, which may also contain any trailers that make up the message.
public enum HTTPRequestPart: Sendable, Hashable {
    case head(HTTPRequest)
    case body(ByteBuffer)
    case end(HTTPFields?)
}

/// The parts of a complete HTTP response.
///
/// An HTTP response message is made up of one or more response headers encoded
/// by `.head`, zero or more body parts, and optionally some trailers.
///
/// To indicate that a complete HTTP message has been sent or received, we use
/// `.end`, which may also contain any trailers that make up the message.
public enum HTTPResponsePart: Sendable, Hashable {
    case head(HTTPResponse)
    case body(ByteBuffer)
    case end(HTTPFields?)
}
