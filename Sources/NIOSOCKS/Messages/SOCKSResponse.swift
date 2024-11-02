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

// MARK: - SOCKSResponse

/// The SOCKS Server's response to the client's request
/// indicating if the request succeeded or failed.
public struct SOCKSResponse: Hashable, Sendable {

    /// The SOCKS protocol version - we currently only support v5.
    public let version: UInt8 = 5

    /// The status of the connection - used to check if the request
    /// succeeded or failed.
    public var reply: SOCKSServerReply

    /// The host address.
    public var boundAddress: SOCKSAddress

    /// Creates a new ``SOCKSResponse``.
    /// - parameter reply: The status of the connection - used to check if the request
    /// succeeded or failed.
    /// - parameter boundAddress: The host address.
    public init(reply: SOCKSServerReply, boundAddress: SOCKSAddress) {
        self.reply = reply
        self.boundAddress = boundAddress
    }
}

extension ByteBuffer {

    mutating func readServerResponse() throws -> SOCKSResponse? {
        try self.parseUnwindingIfNeeded { buffer in
            guard
                try buffer.readAndValidateProtocolVersion() != nil,
                let reply = buffer.readInteger(as: UInt8.self).map({ SOCKSServerReply(value: $0) }),
                try buffer.readAndValidateReserved() != nil,
                let boundAddress = try buffer.readAddressType()
            else {
                return nil
            }
            return .init(reply: reply, boundAddress: boundAddress)
        }
    }

    @discardableResult mutating func writeServerResponse(_ response: SOCKSResponse) -> Int {
        self.writeInteger(response.version) + self.writeInteger(response.reply.value)
            + self.writeInteger(0, as: UInt8.self) + self.writeAddressType(response.boundAddress)
    }

}

// MARK: - SOCKSServerReply

/// Used to indicate if the SOCKS client's connection request succeeded
/// or failed.
public struct SOCKSServerReply: Hashable, Sendable {

    /// The connection succeeded and data can now be transmitted.
    public static let succeeded = SOCKSServerReply(value: 0x00)

    /// The SOCKS server encountered an internal failure.
    public static let serverFailure = SOCKSServerReply(value: 0x01)

    /// The connection to the host was not allowed.
    public static let notAllowed = SOCKSServerReply(value: 0x02)

    /// The host network is not reachable.
    public static let networkUnreachable = SOCKSServerReply(value: 0x03)

    /// The target host was not reachable.
    public static let hostUnreachable = SOCKSServerReply(value: 0x04)

    /// The connection tot he host was refused
    public static let refused = SOCKSServerReply(value: 0x05)

    /// The host address's TTL has expired.
    public static let ttlExpired = SOCKSServerReply(value: 0x06)

    /// The provided command is not supported.
    public static let commandUnsupported = SOCKSServerReply(value: 0x07)

    /// The provided address type is not supported.
    public static let addressUnsupported = SOCKSServerReply(value: 0x08)

    /// The raw `UInt8` status code.
    public var value: UInt8

    /// Creates a new `Reply` from the given raw status code. Common
    /// statuses have convenience variables.
    /// - parameter value: The raw `UInt8` code sent by the SOCKS server.
    public init(value: UInt8) {
        self.value = value
    }
}
