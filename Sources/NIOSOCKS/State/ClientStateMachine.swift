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
}

enum Action: Hashable {
    case waitForMoreData
    case action(ClientAction)
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
        self.state = .inactive
    }
    
    private func unwindIfNeeded<T>(_ buffer: inout ByteBuffer, _ closure: (inout ByteBuffer) throws -> T) rethrows -> T {
        let save = buffer
        do {
            return try closure(&buffer)
        } catch {
            buffer = save
            throw error
        }
    }
    
}

// MARK: - Incoming
extension ClientStateMachine {
    
    mutating func receiveBuffer(_ buffer: inout ByteBuffer) throws -> Action {
        switch self.state {
        case .waitingForAuthenticationMethod(let greeting):
            return try self.handleSelectedAuthenticationMethod(&buffer, greeting: greeting)
        case .waitingForServerResponse(let request):
            return try self.handleServerResponse(&buffer, request: request)
        default:
            throw SOCKSError.UnexpectedRead()
        }
    }
    
    mutating func handleSelectedAuthenticationMethod(_ buffer: inout ByteBuffer, greeting: ClientGreeting) throws -> Action {
        try self.unwindIfNeeded(&buffer) { buffer in
            guard let selected = try buffer.readMethodSelection() else {
                return .waitForMoreData
            }
            guard greeting.methods.contains(selected.method) else {
                throw SOCKSError.InvalidAuthenticationSelection(selection: selected.method)
            }
            self.state = .pendingAuthentication
            return .action(.authenticateIfNeeded(selected.method))
        }
    }
    
    mutating func handleServerResponse(_ buffer: inout ByteBuffer, request: ClientRequest) throws -> Action {
        try self.unwindIfNeeded(&buffer) { buffer in
            guard let response = try buffer.readServerResponse() else {
                return .waitForMoreData
            }
            guard response.reply == .succeeded else {
                throw SOCKSError.ConnectionFailed(reply: response.reply)
            }
            self.state = .active
            return .action(.proxyEstablished)
        }
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
