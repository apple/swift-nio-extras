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
struct ClientRequest: Hashable {
    
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
        written += self.writeInteger(UInt8(0))
        written += self.writeAddressType(request.addressType)
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
public enum AddressType: Hashable {
    
    case address(SocketAddress)
    
    case domain(String, port: UInt16)
    
    /// How many bytes are needed to represent the address, excluding the port
    var size: Int {
        switch self {
        case .address(.v4):
            return 4
        case .address(.v6):
            return 16
        case .address(.unixDomainSocket):
            fatalError("Unsupported")
        case .domain(let domain, port: _):
            return domain.count + 1
        }
    }
}

extension ByteBuffer {
    
    mutating func readAddressType() throws -> AddressType? {
        return try self.parseUnwindingIfNeeded { buffer in
            guard let type = buffer.readInteger(as: UInt8.self) else {
                throw MissingBytes()
            }
            
            switch type {
            case 0x01:
                return try buffer.readIPv4Address()
            case 0x03:
                return try buffer.readDomain()
            case 0x04:
                return try buffer.readIPv6Address()
            default:
                throw SOCKSError.InvalidAddressType(actual: type)
            }
        }
    }
    
    mutating func readIPv4Address() throws -> AddressType? {
        return try self.parseUnwindingIfNeeded { buffer in
            guard
                let bytes = buffer.readSlice(length: 4),
                let port = try buffer.readPort()
            else {
                throw MissingBytes()
            }
            return .address(try .init(packedIPAddress: bytes, port: port))
        }
    }
    
    mutating func readIPv6Address() throws -> AddressType? {
        return try self.parseUnwindingIfNeeded { buffer in
            guard
                let bytes = buffer.readSlice(length: 16),
                let port = try buffer.readPort()
            else {
                throw MissingBytes()
            }
            return .address(try .init(packedIPAddress: bytes, port: port))
        }
    }
    
    mutating func readDomain() throws -> AddressType? {
        return try self.parseUnwindingIfNeeded { buffer in
            guard
                let length = buffer.readInteger(as: UInt8.self),
                let host = buffer.readString(length: Int(length)),
                let port = try buffer.readPort()
            else {
                throw MissingBytes()
            }
            return .domain(host, port: UInt16(port))
        }
    }
    
    mutating func readPort() throws -> Int? {
        return self.readInteger(as: UInt16.self).flatMap { Int($0) }
    }
    
    @discardableResult mutating func writeAddressType(_ type: AddressType) -> Int {
        switch type {
        case .address(.v4(let address)):
            return self.writeInteger(UInt8(1))
                + self.writeInteger(address.address.sin_addr.s_addr, endianness: .little)
                + self.writeInteger(address.address.sin_port, endianness: .little)
        case .address(.v6(let address)):
            return self.writeInteger(UInt8(4))
                + self.writeIPv6Address(address.address)
                + self.writeInteger(address.address.sin6_port, endianness: .little)
        case .address(.unixDomainSocket):
            // enforced in the channel initalisers.
            fatalError("UNIX domain sockets are not supported")
        case .domain(let domain, port: let port):
            return self.writeInteger(UInt8(3))
                + self.writeInteger(UInt8(domain.count))
                + self.writeString(domain)
                + self.writeInteger(port)
        }
    }
    
    @discardableResult mutating func writeIPv6Address(_ addr: sockaddr_in6) -> Int {
        return withUnsafeBytes(of: addr.sin6_addr) { pointer in
            return self.writeBytes(pointer)
        }
    }
}
