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

/// The first message of the username/password sub-negotiation defined in RFC 1929.
///
/// Sent by the client once the server selected ``AuthenticationMethod/usernamePassword``.
/// On the wire this is `VER (0x01) | ULEN | UNAME | PLEN | PASSWD`.
public struct UsernamePasswordRequest: Hashable, Sendable {

    /// The version of the username/password sub-negotiation. This is *not* the SOCKS
    /// protocol version, RFC 1929 defines its own version which is always *1*.
    public let version: UInt8 = 1

    /// The credentials to authenticate with.
    public var credentials: UsernamePasswordCredentials

    /// The username to authenticate with, decoded as UTF-8. See ``UsernamePasswordCredentials/usernameBytes``
    /// for the exact bytes.
    public var username: String { self.credentials.username }

    /// The password to authenticate with, decoded as UTF-8. See ``UsernamePasswordCredentials/passwordBytes``
    /// for the exact bytes.
    public var password: String { self.credentials.password }

    /// Creates a new ``UsernamePasswordRequest``.
    /// - parameter credentials: The credentials to authenticate with.
    public init(credentials: UsernamePasswordCredentials) {
        self.credentials = credentials
    }
}

extension UsernamePasswordRequest: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "UsernamePasswordRequest(\(self.credentials.description))"
    }

    public var debugDescription: String {
        self.description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["credentials": self.credentials], displayStyle: .struct)
    }
}

extension ByteBuffer {

    /// Attempts to read a ``UsernamePasswordRequest`` (RFC 1929) from the buffer.
    ///
    /// If the buffer does not yet contain a complete request nothing is consumed and `nil` is returned.
    /// The username and the password are kept as the exact bytes that were sent, they are not required
    /// to be valid UTF-8, see ``UsernamePasswordCredentials/usernameBytes``.
    ///
    /// RFC 1929 says that the username and the password have at least one byte, this method is deliberately
    /// lenient and also accepts empty values: whether such credentials are acceptable is the server's decision,
    /// and a server should be able to answer a request with empty fields with a failure status
    /// rather than see a protocol error and have to drop the connection. (Real clients do send an empty password.)
    ///
    /// - throws: ``SOCKSError/InvalidSubnegotiationVersion`` if the version is not *1*.
    public mutating func readUsernamePasswordRequest() throws -> UsernamePasswordRequest? {
        try self.parseUnwindingIfNeeded { buffer -> UsernamePasswordRequest? in
            guard try buffer.readAndValidateSubnegotiationVersion() != nil else {
                return nil
            }
            guard let username = buffer.readLengthPrefixedBytes(),
                let password = buffer.readLengthPrefixedBytes()
            else {
                return nil
            }
            return .init(credentials: .init(wireUsername: username, wirePassword: password))
        }
    }

    /// Writes a ``UsernamePasswordRequest`` (RFC 1929) to the buffer.
    /// - returns: The number of bytes written.
    @discardableResult
    public mutating func writeUsernamePasswordRequest(_ request: UsernamePasswordRequest) -> Int {
        var written = self.writeInteger(request.version)
        written += self.writeLengthPrefixedBytes(request.credentials.usernameBytes)
        written += self.writeLengthPrefixedBytes(request.credentials.passwordBytes)
        return written
    }

    private mutating func readLengthPrefixedBytes() -> [UInt8]? {
        guard let length = self.readInteger(as: UInt8.self) else {
            return nil
        }
        return self.readBytes(length: Int(length))
    }

    private mutating func writeLengthPrefixedBytes(_ bytes: [UInt8]) -> Int {
        // The initializers of UsernamePasswordCredentials never let more than 255 bytes in.
        guard let length = UInt8(exactly: bytes.count) else {
            preconditionFailure("UsernamePasswordCredentials fields are at most 255 bytes long")
        }
        return self.writeInteger(length) + self.writeBytes(bytes)
    }

}
