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

extension ByteBuffer {
    
    mutating func parseUnwindingIfNeeded<T>(_ closure: (inout ByteBuffer) throws -> T) rethrows -> T {
        let save = self
        do {
            return try closure(&self)
        } catch {
            self = save
            throw error
        }
    }
    
    mutating func readAndValidateProtocolVersion() throws {
        try self.parseUnwindingIfNeeded { buffer in
            guard let version = buffer.readInteger(as: UInt8.self) else {
                throw SOCKSError.MissingBytes()
            }
            guard version == 0x05 else {
                throw SOCKSError.InvalidProtocolVersion(actual: version)
            }
        }
    }
    
    mutating func readAndValidateReserved() throws {
        try self.parseUnwindingIfNeeded { buffer in
            guard let reserved = buffer.readInteger(as: UInt8.self) else {
                throw SOCKSError.MissingBytes()
            }
            guard reserved == 0x00 else {
                throw SOCKSError.InvalidReservedByte(actual: reserved)
            }
        }
    }
    
}
