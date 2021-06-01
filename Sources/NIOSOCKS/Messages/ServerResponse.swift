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

public struct ServerResponse: Hashable {
    
    public var version: UInt8
    public var reply: Reply
    public var boundAddress: AddressType
    public var boundPort: UInt16
    
    public init(reply: Reply, boundAddress: AddressType, boundPort: UInt16) {
        self.version = 5
        self.reply = reply
        self.boundAddress = boundAddress
        self.boundPort = boundPort
    }
    
    public init?(buffer: inout ByteBuffer) {
        guard
            let version = buffer.readInteger(as: UInt8.self),
            let reply = Reply(buffer: &buffer),
            buffer.readBytes(length: 1) == [0x00],
            let boundAddress = AddressType(buffer: &buffer),
            let boundPort = buffer.readInteger(as: UInt16.self)
        else {
            return nil
        }
        self.version = version
        self.reply = reply
        self.boundAddress = boundAddress
        self.boundPort = boundPort
    }
}

// MARK: - Reply

public struct Reply: Hashable {
    
    static var succeeded = Self(value: 0x00)
    static var serverFailure = Self(value: 0x01)
    static var notAllowed = Self(value: 0x02)
    static var networkUnreachable = Self(value: 0x03)
    static var hostUnreachable = Self(value: 0x04)
    static var refused = Self(value: 0x05)
    static var ttlExpired = Self(value: 0x06)
    static var commandUnsupported = Self(value: 0x07)
    static var addressUnsupported = Self(value: 0x08)
    
    public var value: UInt8
    
    public init(value: UInt8) {
        self.value = value
    }
    
    public init?(buffer: inout ByteBuffer) {
        guard let value = buffer.readInteger(as: UInt8.self) else {
            return nil
        }
        self.value = value
    }
}
