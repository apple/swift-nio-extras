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
    case error
}

enum ClientAction: Hashable {
    case sendGreeting
    case sendRequest
    case proxyEstablished
    case sendData(ByteBuffer)
}

enum Action: Hashable {
    case waitForMoreData
    case action(ClientAction)
}

struct ClientStateMachine {

    private var state: ClientState
    private var authenticationDelegate: SOCKSClientAuthenticationDelegate
    
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
    
    init(authenticationDelegate: SOCKSClientAuthenticationDelegate) {
        self.state = .inactive
        self.authenticationDelegate = authenticationDelegate
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
        do {
            switch self.state {
            case .waitingForAuthenticationMethod(let greeting):
                return try self.handleSelectedAuthenticationMethod(&buffer, greeting: greeting)
            case .waitingForServerResponse(let request):
                return try self.handleServerResponse(&buffer, request: request)
            case .pendingAuthentication:
                return try self.authenticate(&buffer)
            default:
                throw SOCKSError.UnexpectedRead()
            }
        } catch {
            self.state = .error
            throw error
        }
    }
    
    mutating func handleSelectedAuthenticationMethod(_ buffer: inout ByteBuffer, greeting: ClientGreeting) throws -> Action {
        return try self.unwindIfNeeded(&buffer) { buffer -> Action in
            guard let selected = try buffer.readMethodSelection() else {
                return .waitForMoreData
            }
            guard greeting.methods.contains(selected.method) else {
                throw SOCKSError.InvalidAuthenticationSelection(selection: selected.method)
            }
                
            // start authentication with the delegate
            try self.authenticationDelegate.serverSelectedAuthenticationMethod(selected.method)
            self.state = .pendingAuthentication
            return try self.authenticate(&buffer)
        }
    }
    
    mutating func handleServerResponse(_ buffer: inout ByteBuffer, request: ClientRequest) throws -> Action {
        return try self.unwindIfNeeded(&buffer) { buffer -> Action in
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
    
    mutating func authenticate(_ buffer: inout ByteBuffer) throws -> Action {
        return try self.unwindIfNeeded(&buffer) { buffer -> Action in
            let result = try self.authenticationDelegate.handleIncomingData(buffer: &buffer)
            switch result {
            case .needsMoreData:
                self.state = .pendingAuthentication
                return .waitForMoreData
            case .authenticationFailed:
                self.state = .error
                throw SOCKSError.NoValidAuthenticationMethod()
            case .authenticationComplete:
                self.state = .waitingForClientRequest
                return .action(.sendRequest)
            case .respond(let buffer):
                self.state = .pendingAuthentication
                return .action(.sendData(buffer))
            }
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

    mutating func sendClientGreeting(_ greeting: ClientGreeting) {
        assert(self.state == .waitingForClientGreeting)
        self.state = .waitingForAuthenticationMethod(greeting)
    }
    
    mutating func sendClientRequest(_ request: ClientRequest) {
        assert(self.state == .waitingForClientRequest)
        self.state = .waitingForServerResponse(request)
    }
    
}
