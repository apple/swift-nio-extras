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

public struct ClientRequest: Hashable {
    
    public var version: UInt8
    public var command: Command
    public var addressType: AddressType
    public var desiredPort: UInt16
    
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

public enum Command: UInt8 {
    case connect = 0x01
    case bind = 0x02
    case updAssociate = 0x03
}

// MARK: - AddressType

public enum AddressType: Hashable {
    case ipv4([UInt8])
    case domain([UInt8])
    case ipv6([UInt8])
    
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
            self = .ipv4(bytes)
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
