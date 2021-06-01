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

fileprivate enum ClientState {
    case ready
    case waitingForAuthenticationMethod(ClientGreeting)
}

struct ClientStateMachine {

    private var state: ClientState
    
    init() {
        self.state = .ready
    }

    mutating func sendClientGreeting(_ greeting: ClientGreeting) {
        assert(self.state == .ready)
        self.state = .waitingForAuthenticationMethod(greeting)
    }
    
    mutating func recieveMethodSelection(_ message: MethodSelection) {
        switch self.state {
        case .waitingForAuthenticationMethod(let greeting):
            
        default:
            preconditionFailure("Invalid state")
        }
    }
    
    mutating func recieveMethodSelection(_ message: MethodSelection) {
        switch self.state {
        case .waitingForAuthenticationMethod(let greeting):
            
        default:
            preconditionFailure("Invalid state")
        }
    }
    
}
