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

public struct MethodSelection: Hashable {
    public var version: UInt8
    public var method: AuthenticationMethod
    
    public init(method: AuthenticationMethod) {
        self.version = 5
        self.method = method
    }
    
    init?(buffer: inout ByteBuffer) {
        guard
            let version = buffer.readInteger(as: UInt8.self),
            let method = buffer.readInteger(as: UInt8.self)
        else {
            return nil
        }
        self.version = version
        self.method = .init(value: method)
    }
}
