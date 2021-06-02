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

import NIO

// MARK: - ServerResponse

/// The SOCKS Server's response to the client's request
/// indicating if the request succeeded or failed.
struct ServerResponse: Hashable {
    
    /// The SOCKS protocol version - we currently only support v5.
    public let version: UInt8 = 5
    
    /// The status of the connection - used to check if the request
    /// succeeded or failed.
    public var reply: Reply
    
    /// The host address.
    public var boundAddress: AddressType
    
    /// The host port.
    public var boundPort: UInt16
    
    /// Creates a new `ServerResponse`.
    /// - parameter reply: The status of the connection - used to check if the request
    /// succeeded or failed.
    /// - parameter boundAddress: The host address.
    /// - parameter boundPort: The host port.
    public init(reply: Reply, boundAddress: AddressType, boundPort: UInt16) {
        self.reply = reply
        self.boundAddress = boundAddress
        self.boundPort = boundPort
    }
    
    init?(buffer: inout ByteBuffer) throws {
        guard
            let version = buffer.readInteger(as: UInt8.self),
            let reply = Reply(buffer: &buffer),
            let reserved = buffer.readInteger(as: UInt8.self),
            let boundAddress = try AddressType(buffer: &buffer),
            let boundPort = buffer.readInteger(as: UInt16.self)
        else {
            return nil
        }
        
        guard reserved == 0x0 else {
            throw InvalidReservedByte(actual: reserved)
        }
        
        guard version == 0x05 else {
            throw InvalidProtocolVersion(actual: version)
        }
        
        self.reply = reply
        self.boundAddress = boundAddress
        self.boundPort = boundPort
    }
}

// MARK: - Reply

/// Used to indicate if the SOCKS client's connection request succeeded
/// or failed.
public struct Reply: Hashable {
    
    /// The connection succeeded and data can now be transmitted.
    static let succeeded = Reply(value: 0x00)
    
    /// The SOCKS server encountered an internal failure.
    static let serverFailure = Reply(value: 0x01)
    
    /// The connection to the host was not allowed.
    static let notAllowed = Reply(value: 0x02)
    
    /// The host network is not reachable.
    static let networkUnreachable = Reply(value: 0x03)
    
    /// The target host was not reachable.
    static let hostUnreachable = Reply(value: 0x04)
    
    /// The connection tot he host was refused
    static let refused = Reply(value: 0x05)
    
    /// The host address's TTL has expired.
    static let ttlExpired = Reply(value: 0x06)
    
    /// The provided command is not supported.
    static let commandUnsupported = Reply(value: 0x07)
    
    /// The provided address type is not supported.
    static let addressUnsupported = Reply(value: 0x08)
    
    /// The raw `UInt8` status code.
    public let value: UInt8
    
    /// Creates a new `Reply` from the given raw status code. Common
    /// statuses have convenience variables.
    /// - parameter value: The raw `UInt8` code sent by the SOCKS server.
    public init(value: UInt8) {
        self.value = value
    }
    
    init?(buffer: inout ByteBuffer) {
        guard let value = buffer.readInteger(as: UInt8.self) else {
            return nil
        }
        self.value = value
    }
}
