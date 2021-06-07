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

struct MissingBytes: Error {
    
}

extension ByteBuffer {
    
    mutating func parseUnwindingIfNeeded<T>(_ closure: (inout ByteBuffer) throws -> T?) rethrows -> T? {
        let save = self
        do {
            return try closure(&self)
        } catch is MissingBytes {
            self = save
            return nil
        } catch {
            self = save
            throw error
        }
    }
    
    mutating func parseUnwindingIfNeeded<T>(_ closure: (inout ByteBuffer) throws -> T) rethrows -> T {
        let save = self
        do {
            return try closure(&self)
        } catch {
            self = save
            throw error
        }
    }
    
}

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
        case .error, .inactive, .waitingForAuthenticationMethod, .waitingForClientGreeting, .waitingForClientRequest, .waitingForServerResponse:
            return false
        }
    }
    
    var shouldBeginHandshake: Bool  {
        switch self.state {
        case .inactive:
            return true
        case .active, .error, .waitingForAuthenticationMethod, .waitingForClientGreeting, .waitingForClientRequest, .waitingForServerResponse:
            return false
        }
    }
    
    init() {
        self.state = .inactive
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
            case .active, .error, .inactive, .waitingForClientGreeting, .waitingForClientRequest:
                throw SOCKSError.UnexpectedRead()
            }
        } catch {
            self.state = .error
            throw error
        }
    }
    
    mutating func handleSelectedAuthenticationMethod(_ buffer: inout ByteBuffer, greeting: ClientGreeting) throws -> ClientAction {
        return try buffer.parseUnwindingIfNeeded { buffer -> ClientAction in
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
        return try buffer.parseUnwindingIfNeeded { buffer -> ClientAction in
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
        // we don't currently support any authentication
        // so assume all is fine, and instruct the client
        // to send the request
        self.state = .waitingForClientRequest
        return .sendRequest
    }
    
}

// MARK: - Outgoing
extension ClientStateMachine {
    
    mutating func connectionEstablished() throws -> ClientAction {
        guard self.state == .inactive else {
            throw SOCKSError.InvalidState(expected: .inactive, actual: self.state)
        }
        self.state = .waitingForClientGreeting
        return .sendGreeting
    }

    mutating func sendClientGreeting(_ greeting: ClientGreeting) throws {
        guard self.state == .inactive else {
            throw SOCKSError.InvalidState(expected: .waitingForClientGreeting, actual: self.state)
        }
        self.state = .waitingForAuthenticationMethod(greeting)
    }
    
    mutating func sendClientRequest(_ request: ClientRequest) throws {
        guard self.state == .inactive else {
            throw SOCKSError.InvalidState(expected: .waitingForClientRequest, actual: self.state)
        }
        self.state = .waitingForServerResponse(request)
    }
    
}
