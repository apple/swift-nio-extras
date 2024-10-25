//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

/// Clients begin the SOCKS handshake process
/// by providing an array of suggested authentication
/// methods.
public struct ClientGreeting: Hashable, Sendable {

    /// The protocol version.
    public let version: UInt8 = 5

    /// The client-supported authentication methods.
    /// The SOCKS server will select one to use.
    public var methods: [AuthenticationMethod]

    /// Creates a new ``ClientGreeting``
    /// - parameter methods: The client-supported authentication methods.
    public init(methods: [AuthenticationMethod]) {
        self.methods = methods
    }
}

extension ByteBuffer {

    mutating func readClientGreeting() throws -> ClientGreeting? {
        try self.parseUnwindingIfNeeded { buffer in
            guard
                try buffer.readAndValidateProtocolVersion() != nil,
                let numMethods = buffer.readInteger(as: UInt8.self),
                buffer.readableBytes >= numMethods
            else {
                return nil
            }

            // safe to bang as we've already checked the buffer size
            let methods = buffer.readBytes(length: Int(numMethods))!.map { AuthenticationMethod(value: $0) }
            return .init(methods: methods)
        }
    }

    @discardableResult mutating func writeClientGreeting(_ greeting: ClientGreeting) -> Int {
        var written = 0
        written += self.writeInteger(greeting.version)
        written += self.writeInteger(UInt8(greeting.methods.count))

        for method in greeting.methods {
            written += self.writeInteger(method.value)
        }

        return written
    }

}
