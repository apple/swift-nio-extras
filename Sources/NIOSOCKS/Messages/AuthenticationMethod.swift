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

public struct AuthenticationMethod: Hashable {
    
    /// No authentication required
    public static var noneRequired = Self(value: 0x00)
    
    /// Use GSSAPI
    public static var gssAPI = Self(value: 0x01)
    
    /// Username / password authentication
    public static var usernamePassword = Self(value: 0x02)
    
    /// No acceptable authentication methods
    public static var noneAcceptable = Self(value: 0xFF)
    
    /// The method identifier, valid values are in the range 0:255.
    public var value: UInt8
    
}

extension ByteBuffer {
    
    @discardableResult mutating func writeClientGreeting(_ greeting: ClientGreeting) -> Int {
        self.writeInteger(greeting.version)
        
        assert(greeting.methods.count <= 255)
        self.writeInteger(UInt8(greeting.methods.count))
        
        for method in greeting.methods {
            self.writeInteger(method.value)
        }
        
        return 2 + greeting.methods.count
    }
    
}
