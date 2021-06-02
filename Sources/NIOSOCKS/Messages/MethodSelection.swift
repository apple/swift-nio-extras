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

/// Used by the SOCKS server to inform the client which
/// authentication method it would like to use out of those
/// offered.
struct MethodSelection: Hashable {
    
    /// The SOCKS protocol version - we currently only support v5.
    public let version: UInt8 = 5
    
    /// The server's selected authentication method.
    public var method: AuthenticationMethod
    
    /// Creates a new `MethodSelection` wrapping an `AuthenticationMethod`.
    /// - parameter method: The selected `AuthenticationMethod`.
    public init(method: AuthenticationMethod) {
        self.method = method
    }
}

extension ByteBuffer {
    
    mutating func readMethodSelection() throws -> MethodSelection? {
        guard
            let version = self.readInteger(as: UInt8.self),
            let method = self.readInteger(as: UInt8.self)
        else {
            return nil
        }
        
        guard version == 0x05 else {
            throw InvalidProtocolVersion(actual: version)
        }
        
        return .init(method: .init(value: method))
    }
    
}
