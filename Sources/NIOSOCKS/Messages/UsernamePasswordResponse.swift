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

import NIOCore

/// The server's answer to a ``UsernamePasswordRequest``, as defined by RFC 1929.
/// On the wire this is `VER (0x01) | STATUS`.
public struct UsernamePasswordResponse: Hashable, Sendable {

    /// The version of the username/password sub-negotiation, always *1*.
    public let version: UInt8 = 1

    /// The status reported by the server. *0* means the credentials were accepted,
    /// any other value means they were rejected and the connection must be closed.
    public var status: UInt8

    /// Whether the server accepted the credentials.
    public var isSuccess: Bool { self.status == 0x00 }

    /// A response indicating that the credentials were accepted.
    public static let success = UsernamePasswordResponse(status: 0x00)

    /// A response indicating that the credentials were rejected.
    public static let failure = UsernamePasswordResponse(status: 0x01)

    /// Creates a new ``UsernamePasswordResponse``.
    /// - parameter status: *0* if the credentials were accepted, any other value if they were rejected.
    public init(status: UInt8) {
        self.status = status
    }
}

extension ByteBuffer {

    /// Attempts to read a ``UsernamePasswordResponse`` (RFC 1929) from the buffer.
    ///
    /// If the buffer does not yet contain a complete response nothing is consumed and `nil` is returned.
    ///
    /// - throws: ``SOCKSError/InvalidSubnegotiationVersion`` if the version is not *1*.
    public mutating func readUsernamePasswordResponse() throws -> UsernamePasswordResponse? {
        try self.parseUnwindingIfNeeded { buffer -> UsernamePasswordResponse? in
            guard
                try buffer.readAndValidateSubnegotiationVersion() != nil,
                let status = buffer.readInteger(as: UInt8.self)
            else {
                return nil
            }
            return .init(status: status)
        }
    }

    /// Writes a ``UsernamePasswordResponse`` (RFC 1929) to the buffer.
    /// - returns: The number of bytes written.
    @discardableResult
    public mutating func writeUsernamePasswordResponse(_ response: UsernamePasswordResponse) -> Int {
        self.writeInteger(response.version) + self.writeInteger(response.status)
    }

}
