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

/// The SOCKS handshake begins with the client sending a greeting
/// containing supported authentication methods.
public struct ClientGreeting: Hashable {
    
    /// The SOCKS protocol version - we currently only support v5.
    public let version: UInt8 = 5
    
    /// The client's supported authentication methods, defined in RFC 1928.
    public var methods: [AuthenticationMethod]
    
    /// Creates a new client greeting with the given authentication methods.
    /// - parameter methods: The client's supported authentication methods.
    public init(methods: [AuthenticationMethod]) {
        self.methods = methods
    }
}

extension ByteBuffer {
    
    mutating func readClientGreeting() throws -> ClientGreeting? {
        guard
            let version = self.readInteger(as: UInt8.self),
            let numMethods = self.readInteger(as: UInt8.self)
        else {
            return nil
        }
        
        guard version == 5 else {
            throw InvalidProtocolVersion(actual: version)
        }
        
        var methods: [AuthenticationMethod] = []
        methods.reserveCapacity(Int(numMethods))
        for _ in 0..<numMethods {
            guard let method = self.readInteger(as: UInt8.self) else {
                return nil
            }
            methods.append(.init(value: method))
        }
        return .init(methods: methods)
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
