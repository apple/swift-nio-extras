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

struct ClientGreeting: Hashable {
    let version: UInt8 = 5
    var methods: [AuthenticationMethod]
}

extension ByteBuffer {
    
    mutating func readClientGreeting() throws -> ClientGreeting? {
        return try self.parseUnwindingIfNeeded { buffer in
            guard
                let version = buffer.readInteger(as: UInt8.self),
                let numMethods = buffer.readInteger(as: UInt8.self)
            else {
                throw MissingBytes()
            }
            
            guard version == 5 else {
                throw SOCKSError.InvalidProtocolVersion(actual: version)
            }
            
            var methods: [AuthenticationMethod] = []
            methods.reserveCapacity(Int(numMethods))
            for _ in 0..<numMethods {
                guard let method = buffer.readInteger(as: UInt8.self) else {
                    throw MissingBytes()
                }
                methods.append(.init(value: method))
            }
            return .init(methods: methods)
        }
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
