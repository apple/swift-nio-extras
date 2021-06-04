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
    case waitingForClientRequest
    case waitingForServerResponse(ClientRequest)
    case active
    case error
}

enum ClientAction: Hashable {
    case waitForMoreData
    case sendGreeting
    case sendRequest
    case proxyEstablished
    case sendData(ByteBuffer)
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
    
    mutating func receiveBuffer(_ buffer: inout ByteBuffer) throws -> ClientAction {
        do {
            switch self.state {
            case .waitingForAuthenticationMethod(let greeting):
                return try self.handleSelectedAuthenticationMethod(&buffer, greeting: greeting)
            case .waitingForServerResponse(let request):
                return try self.handleServerResponse(&buffer, request: request)
            default:
                throw SOCKSError.UnexpectedRead()
            }
        } catch {
            self.state = .error
            throw error
        }
    }
    
    mutating func handleSelectedAuthenticationMethod(_ buffer: inout ByteBuffer, greeting: ClientGreeting) throws -> ClientAction {
        return try self.unwindIfNeeded(&buffer) { buffer -> ClientAction in
            guard let selected = try buffer.readMethodSelection() else {
                return .waitForMoreData
            }
            guard greeting.methods.contains(selected.method) else {
                throw SOCKSError.InvalidAuthenticationSelection(selection: selected.method)
            }
                
            // we don't current support any form of authentication
            return self.authenticate(&buffer)
        }
    }
    
    mutating func handleServerResponse(_ buffer: inout ByteBuffer, request: ClientRequest) throws -> ClientAction {
        return try self.unwindIfNeeded(&buffer) { buffer -> ClientAction in
            guard let response = try buffer.readServerResponse() else {
                return .waitForMoreData
            }
            guard response.reply == .succeeded else {
                throw SOCKSError.ConnectionFailed(reply: response.reply)
            }
            self.state = .active
            return .proxyEstablished
        }
    }
    
    mutating func authenticate(_ buffer: inout ByteBuffer) -> ClientAction {
        return self.unwindIfNeeded(&buffer) { buffer -> ClientAction in
            
            // we don't currently support any authentication
            // so assume all is fine, and instruct the client
            // to send the request
            self.state = .waitingForClientRequest
            return .sendRequest
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
