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

public enum SOCKSError {
    
    public struct InvalidState: Error, Hashable {
        var expected: ClientState
        var actual: ClientState
    }
    
    public struct InvalidProtocolVersion: Error, Hashable {
        public var actual: UInt8
        public init(actual: UInt8) {
            self.actual = actual
        }
    }

    public struct InvalidReservedByte: Error, Hashable {
        public var actual: UInt8
        public init(actual: UInt8) {
            self.actual = actual
        }
    }

    public struct InvalidAddressType: Error, Hashable {
        public var actual: UInt8
        public init(actual: UInt8) {
            self.actual = actual
        }
    }

    public struct InvalidAuthenticationSelection: Error, Hashable {
        public var selection: AuthenticationMethod
        public init(selection: AuthenticationMethod) {
            self.selection = selection
        }
    }

    public struct NoValidAuthenticationMethod: Error, Hashable {
        public init() {
            
        }
    }

    public struct ConnectionFailed: Error, Hashable {
        public var reply: SOCKSServerReply
        public init(reply: SOCKSServerReply) {
            self.reply = reply
        }
    }
    
    public struct UnexpectedRead: Error, Hashable {
        public init() {
            
        }
    }
    
    public struct UnexpectedAuthenticationMethod: Error, Hashable {
        public var expected: [AuthenticationMethod]
        public var actual: AuthenticationMethod
        
        public init(expected: [AuthenticationMethod], actual: AuthenticationMethod) {
            self.expected = expected
            self.actual = actual
        }
    }
    
}
