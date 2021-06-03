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

enum ClientState: Hashable {
    case inactive
    case waitingForClientGreeting
    case waitingForAuthenticationMethod(ClientGreeting)
    case pendingAuthentication
    case waitingForClientRequest
    case waitingForServerResponse(ClientRequest)
    case active
}

enum ClientAction: Hashable {
    case sendGreeting
    case authenticateIfNeeded(AuthenticationMethod)
    case sendRequest
    case proxyEstablished
    case waitForMoreData
}

struct ClientStateMachine {

    private var state: ClientState
    
    var proxyEstablished: Bool {
        switch self.state {
        case .active:
            return true
        default:
            return false
        }
    }
    
    var shouldBeginHandshake: Bool  {
        switch self.state {
        case .inactive:
            return true
        default:
            return false
        }
    }
    
    init() {
        self.state = .waitingForClientGreeting
    }
    
}

// MARK: - Incoming
extension ClientStateMachine {
    
    mutating func receiveBuffer(_ buffer: inout ByteBuffer) throws -> ClientAction {
        switch self.state {
        case .waitingForAuthenticationMethod(let greeting):
            return try self.handleSelectedAuthenticationMethod(&buffer, greeting: greeting)
        case .waitingForServerResponse(let request):
            return try self.handleServerResponse(&buffer, request: request)
        default:
            preconditionFailure("Invalid state")
        }
    }
    
    mutating func handleSelectedAuthenticationMethod(_ buffer: inout ByteBuffer, greeting: ClientGreeting) throws -> ClientAction {
        let save = buffer
        guard let selected = try buffer.readMethodSelection() else {
            buffer = save
            return .waitForMoreData
        }
        guard greeting.methods.contains(selected.method) else {
            buffer = save
            throw SOCKSError.InvalidAuthenticationSelection(selection: selected.method)
        }
        self.state = .pendingAuthentication
        return .authenticateIfNeeded(selected.method)
    }
    
    mutating func handleServerResponse(_ buffer: inout ByteBuffer, request: ClientRequest) throws -> ClientAction {
        let save = buffer
        guard let response = try buffer.readServerResponse() else {
            buffer = save
            return .waitForMoreData
        }
        guard response.reply == .succeeded else {
            buffer = save
            throw SOCKSError.ConnectionFailed(reply: response.reply)
        }
        self.state = .active
        return .proxyEstablished
    }
    
}

// MARK: - Outgoing
extension ClientStateMachine {
    
    mutating func connectionEstablished() -> ClientAction {
        assert(self.state == .inactive)
        self.state = .waitingForClientGreeting
        return .sendGreeting
    }
    
    mutating func authenticationComplete() -> ClientAction {
        assert(self.state == .pendingAuthentication)
        self.state = .waitingForClientRequest
        return .sendRequest
    }

    mutating func sendClientGreeting(_ greeting: ClientGreeting) {
        assert(self.state == .waitingForClientGreeting)
        self.state = .waitingForAuthenticationMethod(greeting)
    }
    
    mutating func sendClientRequest(_ request: ClientRequest) {
        assert(self.state == .waitingForClientRequest)
        self.state = .waitingForServerResponse(request)
    }
    
}
