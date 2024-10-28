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

import NIOHPACK
import NIOHTTP2

extension HPACKHeaders {
    /// Whether this `HTTPHeaders` corresponds to a final response or not.
    ///
    /// This function is only valid if called on a response header block. If the :status header
    /// is not present, this will throw.
    fileprivate func isInformationalResponse() throws -> Bool {
        try self.peekPseudoHeader(name: ":status").first! == "1"
    }

    /// Grabs a pseudo-header from a header block. Does not remove it.
    ///
    /// - Parameters:
    ///   - name: The header name to find.
    /// - Returns: The value for this pseudo-header.
    /// - Throws: `NIOHTTP2Errors` if there is no such header, or multiple.
    internal func peekPseudoHeader(name: String) throws -> String {
        // This could be done with .lazy.filter.map but that generates way more ARC traffic.
        var headerValue: String? = nil

        for (fieldName, fieldValue, _) in self {
            if name == fieldName {
                guard headerValue == nil else {
                    throw NIOHTTP2Errors.duplicatePseudoHeader(name)
                }
                headerValue = fieldValue
            }
        }

        if let headerValue {
            return headerValue
        } else {
            throw NIOHTTP2Errors.missingPseudoHeader(name)
        }
    }
}

/// A state machine that keeps track of the header blocks sent or received and that determines the type of any
/// new header block.
struct HTTP2HeadersStateMachine {
    /// The list of possible header frame types.
    ///
    /// This is used in combination with introspection of the HTTP header blocks to determine what HTTP header block
    /// a certain HTTP header is.
    enum HeaderType {
        /// A request header block.
        case requestHead

        /// An informational response header block. These can be sent zero or more times.
        case informationalResponseHead

        /// A final response header block.
        case finalResponseHead

        /// A trailer block. Once this is sent no further header blocks are acceptable.
        case trailer
    }

    /// The previous header block.
    private var previousHeader: HeaderType?

    /// The mode of this connection: client or server.
    private let mode: NIOHTTP2Handler.ParserMode

    init(mode: NIOHTTP2Handler.ParserMode) {
        self.mode = mode
    }

    /// Called when about to process an HTTP headers block to determine its type.
    mutating func newHeaders(block: HPACKHeaders) throws -> HeaderType {
        let newType: HeaderType

        switch (self.mode, self.previousHeader) {
        case (.server, .none):
            // The first header block received on a server mode stream must be a request block.
            newType = .requestHead
        case (.client, .none),
            (.client, .some(.informationalResponseHead)):
            // The first header block received on a client mode stream may be either informational or final,
            // depending on the value of the :status pseudo-header. Alternatively, if the previous
            // header block was informational, the same possibilities apply.
            newType = try block.isInformationalResponse() ? .informationalResponseHead : .finalResponseHead
        case (.server, .some(.requestHead)),
            (.client, .some(.finalResponseHead)):
            // If the server has already received a request head, or the client has already received a final response,
            // this is a trailer block.
            newType = .trailer
        case (.server, .some(.informationalResponseHead)),
            (.server, .some(.finalResponseHead)),
            (.client, .some(.requestHead)):
            // These states should not be reachable!
            preconditionFailure("Invalid internal state!")
        case (.server, .some(.trailer)),
            (.client, .some(.trailer)):
            // TODO(cory): This should probably throw, as this can happen in malformed programs without the world ending.
            preconditionFailure("Sending too many header blocks.")
        }

        self.previousHeader = newType
        return newType
    }
}
