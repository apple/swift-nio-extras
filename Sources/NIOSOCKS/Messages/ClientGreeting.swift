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
    public var version: UInt8
    
    /// The client's supported authentication methods, defined in RFC 1928.
    public var methods: [AuthenticationMethod]
    
    /// Creates a new client greeting with the given authentication methods.
    /// - parameter methods: The client's supported authentication methods.
    public init(methods: [AuthenticationMethod]) {
        self.version = 5
        self.methods = methods
    }
    
    init?(buffer: inout ByteBuffer) {
        guard
            let version = buffer.readInteger(as: UInt8.self),
            let numMethods = buffer.readInteger(as: UInt8.self)
        else {
            return nil
        }
        
        var methods: [AuthenticationMethod] = []
        methods.reserveCapacity(Int(numMethods))
        for _ in 0..<numMethods {
            guard let method = buffer.readInteger(as: UInt8.self) else {
                return nil
            }
            methods.append(.init(value: method))
        }
        self.version = version
        self.methods = methods
    }
}

extension ByteBuffer {
    
    @discardableResult mutating func writeClientGreeting(_ greeting: ClientGreeting) -> Int {
        self.writeInteger(greeting.version)
        
        assert(greeting.methods.count > 0 && greeting.methods.count <= 255)
        self.writeInteger(UInt8(greeting.methods.count))
        
        for method in greeting.methods {
            self.writeInteger(method.value)
        }
        
        return 2 + greeting.methods.count
    }
    
}