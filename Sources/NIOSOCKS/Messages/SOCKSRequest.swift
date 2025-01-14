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

import CNIOLinux
import NIOCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#else
import Glibc
#endif

// MARK: - ClientRequest

/// Instructs the SOCKS proxy server of the target host,
/// and how to connect.
public struct SOCKSRequest: Hashable, Sendable {

    /// The SOCKS protocol version - we currently only support v5.
    public let version: UInt8 = 5

    /// How to connect to the host.
    public var command: SOCKSCommand

    /// The target host address.
    public var addressType: SOCKSAddress

    /// Creates a new ``SOCKSRequest``.
    /// - parameter command: How to connect to the host.
    /// - parameter addressType: The target host address.
    public init(command: SOCKSCommand, addressType: SOCKSAddress) {
        self.command = command
        self.addressType = addressType
    }

}

extension ByteBuffer {

    @discardableResult mutating func writeClientRequest(_ request: SOCKSRequest) -> Int {
        var written = self.writeInteger(request.version)
        written += self.writeInteger(request.command.value)
        written += self.writeInteger(UInt8(0))
        written += self.writeAddressType(request.addressType)
        return written
    }

    @discardableResult mutating func readClientRequest() throws -> SOCKSRequest? {
        try self.parseUnwindingIfNeeded { buffer -> SOCKSRequest? in
            guard
                try buffer.readAndValidateProtocolVersion() != nil,
                let command = buffer.readInteger(as: UInt8.self),
                try buffer.readAndValidateReserved() != nil,
                let address = try buffer.readAddressType()
            else {
                return nil
            }
            return .init(command: .init(value: command), addressType: address)
        }
    }

}

// MARK: - SOCKSCommand

/// What type of connection the SOCKS server should establish with
/// the target host.
public struct SOCKSCommand: Hashable, Sendable {

    /// Typically the primary connection type, suitable for HTTP.
    public static let connect = SOCKSCommand(value: 0x01)

    /// Used in protocols that require the client to accept connections
    /// from the server, e.g. FTP.
    public static let bind = SOCKSCommand(value: 0x02)

    /// Used to establish an association within the UDP relay process to
    /// handle UDP datagrams.
    public static let udpAssociate = SOCKSCommand(value: 0x03)

    /// Command value as defined in RFC
    public var value: UInt8

    public init(value: UInt8) {
        self.value = value
    }
}

// MARK: - SOCKSAddress

/// The address used to connect to the target host.
public enum SOCKSAddress: Hashable, Sendable {
    /// Socket Adress
    case address(SocketAddress)
    /// Host and port
    case domain(String, port: Int)

    static let ipv4IdentifierByte: UInt8 = 0x01
    static let domainIdentifierByte: UInt8 = 0x03
    static let ipv6IdentifierByte: UInt8 = 0x04

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
            // the +1 is for the leading "count" byte
            // containing how many UTF8 bytes are in the
            // domain
            return domain.utf8.count + 1
        }
    }
}

extension ByteBuffer {

    mutating func readAddressType() throws -> SOCKSAddress? {
        try self.parseUnwindingIfNeeded { buffer in
            guard let type = buffer.readInteger(as: UInt8.self) else {
                return nil
            }

            switch type {
            case SOCKSAddress.ipv4IdentifierByte:
                return try buffer.readIPv4Address()
            case SOCKSAddress.domainIdentifierByte:
                return buffer.readDomain()
            case SOCKSAddress.ipv6IdentifierByte:
                return try buffer.readIPv6Address()
            default:
                throw SOCKSError.InvalidAddressType(actual: type)
            }
        }
    }

    mutating func readIPv4Address() throws -> SOCKSAddress? {
        try self.parseUnwindingIfNeeded { buffer in
            guard
                let bytes = buffer.readSlice(length: 4),
                let port = buffer.readPort()
            else {
                return nil
            }
            return .address(try .init(packedIPAddress: bytes, port: port))
        }
    }

    mutating func readIPv6Address() throws -> SOCKSAddress? {
        try self.parseUnwindingIfNeeded { buffer in
            guard
                let bytes = buffer.readSlice(length: 16),
                let port = buffer.readPort()
            else {
                return nil
            }
            return .address(try .init(packedIPAddress: bytes, port: port))
        }
    }

    mutating func readDomain() -> SOCKSAddress? {
        self.parseUnwindingIfNeeded { buffer in
            guard
                let length = buffer.readInteger(as: UInt8.self),
                let host = buffer.readString(length: Int(length)),
                let port = buffer.readPort()
            else {
                return nil
            }
            return .domain(host, port: port)
        }
    }

    mutating func readPort() -> Int? {
        guard let port = self.readInteger(as: UInt16.self) else {
            return nil
        }
        return Int(port)
    }

    @discardableResult mutating func writeAddressType(_ type: SOCKSAddress) -> Int {
        switch type {
        case .address(.v4(let address)):
            return self.writeInteger(SOCKSAddress.ipv4IdentifierByte)
                + self.writeIPv4Address(address.address)
                + self.writeInteger(UInt16(bigEndian: address.address.sin_port))
        case .address(.v6(let address)):
            return self.writeInteger(SOCKSAddress.ipv6IdentifierByte)
                + self.writeIPv6Address(address.address)
                + self.writeInteger(UInt16(bigEndian: address.address.sin6_port))
        case .address(.unixDomainSocket):
            // enforced in the channel initalisers.
            fatalError("UNIX domain sockets are not supported")
        case .domain(let domain, let port):
            return self.writeInteger(SOCKSAddress.domainIdentifierByte)
                + self.writeInteger(UInt8(domain.utf8.count))
                + self.writeString(domain)
                + self.writeInteger(UInt16(port))
        }
    }

    @discardableResult mutating func writeIPv6Address(_ addr: sockaddr_in6) -> Int {
        withUnsafeBytes(of: addr.sin6_addr) { pointer in
            self.writeBytes(pointer)
        }
    }

    @discardableResult mutating func writeIPv4Address(_ addr: sockaddr_in) -> Int {
        withUnsafeBytes(of: addr.sin_addr) { pointer in
            self.writeBytes(pointer)
        }
    }
}
