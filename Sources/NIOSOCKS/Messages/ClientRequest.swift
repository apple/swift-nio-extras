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
    public var version: UInt8
    
    /// How to connect to the host.
    public var command: Command
    
    /// The target host address.
    public var addressType: AddressType
    
    /// The target host port.
    public var desiredPort: UInt16
    
    /// Creates a new `ClientRequest`.
    /// - parameter command: How to connect to the host.
    /// - parameter addressType: The target host address.
    /// - parameter desiredPort: The target host port.
    public init(command: Command, addressType: AddressType, desiredPort: UInt16) {
        self.version = 5
        self.command = command
        self.addressType = addressType
        self.desiredPort = desiredPort
    }
    
}

extension ByteBuffer {
    
    @discardableResult mutating func writeClientRequest(_ request: ClientRequest) -> Int {
        self.writeInteger(request.version)
        self.writeInteger(request.command.rawValue)
        self.writeInteger(0, as: UInt8.self)
        let addressSize = self.writeAddressType(request.addressType)
        self.writeInteger(request.desiredPort)
        return 1 + 1 + 2 + addressSize + 2
    }
    
}

// MARK: - Command

/// What type of connection the SOCKS server should establish with
/// the target host.
enum Command: UInt8 {
    
    /// Typically the primary connection type, suitable for HTTP.
    case connect = 0x01
    
    /// Used in protocols that require the client to accept connections
    /// from the server, e.g. FTP.
    case bind = 0x02
    
    /// Used to establish an association within the UDP relay process to
    /// handle UDP datagrams.
    case updAssociate = 0x03
}

// MARK: - AddressType

/// The address used to connect to the target host.
public enum AddressType: Hashable {
    
    /// An IPv4 address (4 bytes), e.g. *192.168.1.2*
    case ipv4([UInt8])
    
    /// A fullly-qualified domain name, e.g. *apple.com*
    case domain([UInt8])
    
    /// An IPv6 address (16 bytes), e.g. *aaaa:bbbb:cccc:dddd*
    case ipv6([UInt8])
    
    /// How many bytes are needed to represent the address
    var size: Int {
        switch self {
        case .domain(let domain):
            return domain.count + 1
        case .ipv4:
            return 4
        case .ipv6:
            return 16
        }
    }
    
    init?(buffer: inout ByteBuffer) {
        guard let type = buffer.readInteger(as: UInt8.self) else {
            return nil
        }
        
        switch type {
        case 0x01:
            guard let bytes = buffer.readBytes(length: 4) else {
                return nil
            }
            self = .ipv4(bytes)
        case 0x03:
            guard
                let length = buffer.readInteger(as: UInt8.self),
                let bytes = buffer.readBytes(length: Int(length))
            else {
                return nil
            }
            self = .domain(bytes)
        case 0x04:
            guard let bytes = buffer.readBytes(length: 16) else {
                return nil
            }
            self = .ipv6(bytes)
        default:
            fatalError("Unknown address type \(type)")
        }
    }
}

extension ByteBuffer {
    
    @discardableResult mutating func writeAddressType(_ type: AddressType) -> Int {
        switch type {
        case .ipv4(let bytes):
            self.writeInteger(UInt8(1))
            self.writeBytes(bytes)
            return 1 + 4
        case .domain(let bytes):
            self.writeInteger(UInt8(3))
            self.writeInteger(UInt8(bytes.count))
            self.writeBytes(bytes)
            return 1 + 1 + bytes.count
        case .ipv6(let bytes):
            self.writeInteger(UInt8(4))
            self.writeBytes(bytes)
            return 1 + 16
        }
    }
    
}
