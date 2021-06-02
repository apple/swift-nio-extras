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

// MARK: - ClientRequest

/// Instructs the SOCKS proxy server of the target host,
/// and how to connect.
public struct ClientRequest: Hashable {
    
    /// The SOCKS protocol version - we currently only support v5.
    public let version: UInt8 = 5
    
    /// How to connect to the host.
    public var command: Command
    
    /// The target host address.
    public var addressType: AddressType
    
    /// Creates a new `ClientRequest`.
    /// - parameter command: How to connect to the host.
    /// - parameter addressType: The target host address.
    /// - parameter desiredPort: The target host port.
    public init(command: Command, addressType: AddressType) {
        self.command = command
        self.addressType = addressType
    }
    
}

extension ByteBuffer {
    
    @discardableResult mutating func writeClientRequest(_ request: ClientRequest) -> Int {
        var written = 0
        written += self.writeInteger(request.version)
        written += self.writeInteger(request.command.value)
        written += self.writeInteger(0, as: UInt8.self)
        written +=  self.writeAddressType(request.addressType)
        return written
    }
    
}

// MARK: - Command

/// What type of connection the SOCKS server should establish with
/// the target host.
public struct Command: Hashable {
    
    /// Typically the primary connection type, suitable for HTTP.
    public static let connect = Command(value: 0x01)
    
    /// Used in protocols that require the client to accept connections
    /// from the server, e.g. FTP.
    public static let bind = Command(value: 0x02)
    
    /// Used to establish an association within the UDP relay process to
    /// handle UDP datagrams.
    public static let udpAssociate = Command(value: 0x03)
    
    public var value: UInt8
}

// MARK: - AddressType

/// The address used to connect to the target host.
public struct AddressType: Hashable {
    
    public var address: SocketAddress
    
    /// How many bytes are needed to represent the address
    public var size: Int {
        switch address {
        case .v4:
            return 4
        case .v6:
            return 16
        case .unixDomainSocket:
            fatalError("Unsupported")
        }
    }
    
    public init(address: SocketAddress) {
        self.address = address
    }
}

extension ByteBuffer {
    
    mutating func readAddresType() throws -> AddressType? {
        guard let type = self.readInteger(as: UInt8.self) else {
            return nil
        }
        
        switch type {
        case 0x01:
            return try self.readIPv4Address()
        case 0x03:
            return try self.readDomain()
        case 0x04:
            return try self.readIPv6Address()
        default:
            throw InvalidAddressType(actual: type)
        }
    }
    
    mutating func readIPv4Address() throws -> AddressType? {
        guard
            let bytes = self.readBytes(length: 4),
            let port = try self.readPort()
        else {
            return nil
        }
        return .init(address: try .init(packedIPAddress: ByteBuffer(bytes: bytes), port: port))
    }
    
    mutating func readIPv6Address() throws -> AddressType? {
        guard
            let bytes = self.readBytes(length: 16),
            let port = try self.readPort()
        else {
            return nil
        }
        return .init(address: try .init(packedIPAddress: ByteBuffer(bytes: bytes), port: port))
    }
    
    mutating func readDomain() throws -> AddressType? {
        guard
            let length = self.readInteger(as: UInt8.self),
            let bytes = self.readBytes(length: Int(length)),
            let port = try self.readPort()
        else {
            return nil
        }
        let host = String(decoding: bytes, as: Unicode.UTF8.self)
        return .init(address: try .makeAddressResolvingHost(host, port: port))
    }
    
    mutating func readPort() throws -> Int? {
        return self.readInteger(as: UInt16.self).flatMap { Int($0)}
    }
    
    @discardableResult mutating func writeAddressType(_ type: AddressType) -> Int {
        switch type.address {
        case .v4(let address):
            return self.writeInteger(UInt8(1))
                + self.writeInteger(address.address.sin_addr.s_addr, endianness: .little)
                + self.writeInteger(address.address.sin_port, endianness: .little)
        case .v6(let address):
            let (p1, p2, p3, p4) = address.address.sin6_addr.__u6_addr.__u6_addr32
            return self.writeInteger(UInt8(4))
                + self.writeInteger(p1, endianness: .little)
                + self.writeInteger(p2, endianness: .little)
                + self.writeInteger(p3, endianness: .little)
                + self.writeInteger(p4, endianness: .little)
                + self.writeInteger(address.address.sin6_port, endianness: .little)
        case .unixDomainSocket:
            fatalError("unsupported")
        }
    }
    
}
