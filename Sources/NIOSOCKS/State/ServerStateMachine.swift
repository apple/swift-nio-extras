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

enum ServerState: Hashable {
    case inactive
    case waitingForClientGreeting
    case waitingToSendAuthenticationMethod
    case authenticating
    case waitingForClientRequest
    case waitingToSendResponse
    case active
    case error
}

struct ServerStateMachine: Hashable {
    
    private var state: ServerState
    
    var proxyEstablished: Bool {
        switch self.state {
        case .active:
            return true
        case .inactive,
             .waitingForClientGreeting,
             .waitingToSendAuthenticationMethod,
             .authenticating,
             .waitingForClientRequest,
             .waitingToSendResponse,
             .error:
            return false
        }
    }
    
    var isAuthenticated: Bool {
        switch self.state {
        case .inactive, .waitingForClientGreeting, .waitingToSendAuthenticationMethod, .authenticating, .error:
            return false
        case .waitingForClientRequest, .waitingToSendResponse, .active:
            return true
        }
    }
    
    init() {
        self.state = .inactive
    }
}

// MARK: - Inbound
extension ServerStateMachine {
    
    mutating func receiveBuffer(_ buffer: inout ByteBuffer) throws -> ClientMessage? {
        do {
            switch self.state {
            case .inactive, .waitingToSendAuthenticationMethod, .waitingToSendResponse, .active, .error:
                throw SOCKSError.UnexpectedRead()
            case .waitingForClientGreeting:
                return try self.handleClientGreeting(from: &buffer)
            case .authenticating:
                return self.handleAuthenticationData(from: &buffer)
            case .waitingForClientRequest:
                return try self.handleClientRequest(from: &buffer)
            }
        } catch {
            self.state = .error
            throw error
        }
    }
    
    fileprivate  mutating func handleClientGreeting(from buffer: inout ByteBuffer) throws -> ClientMessage? {
        return try buffer.parseUnwindingIfNeeded { buffer -> ClientMessage? in
            guard let greeting = try buffer.readClientGreeting() else {
                return nil
            }
            self.state = .waitingToSendAuthenticationMethod
            return .greeting(greeting)
        }
    }
    
    fileprivate mutating func handleClientRequest(from buffer: inout ByteBuffer) throws -> ClientMessage? {
        return try buffer.parseUnwindingIfNeeded { buffer -> ClientMessage? in
            guard let request = try buffer.readClientRequest() else {
                return nil
            }
            self.state = .waitingToSendResponse
            return .request(request)
        }
    }
    
    fileprivate mutating func handleAuthenticationData(from buffer: inout ByteBuffer) -> ClientMessage? {
        guard let buffer = buffer.readSlice(length: buffer.readableBytes) else {
            return nil
        }
        return .authenticationData(buffer)
    }
    
}

// MARK: - Outbound
extension ServerStateMachine {
    
    mutating func connectionEstablished() throws {
        switch self.state {
        case .inactive:
            ()
        case .authenticating,
             .waitingForClientGreeting,
             .waitingToSendAuthenticationMethod,
             .waitingForClientRequest,
             .waitingToSendResponse,
             .active,
             .error:
             throw SOCKSError.InvalidServerState()
        }
        self.state = .waitingForClientGreeting
    }
    
    mutating func sendAuthenticationMethod(_ method: SelectedAuthenticationMethod) throws {
        switch self.state {
        case .waitingToSendAuthenticationMethod:
            ()
        case .inactive,
             .waitingForClientGreeting,
             .authenticating,
             .waitingForClientRequest,
             .waitingToSendResponse,
             .active,
             .error:
             throw SOCKSError.InvalidServerState()
        }
        self.state = .authenticating
    }
    
    mutating func sendServerResponse(_ response: SOCKSResponse) throws {
        switch self.state {
        case .waitingToSendResponse:
            ()
        case .inactive,
             .waitingForClientGreeting,
             .waitingToSendAuthenticationMethod,
             .waitingForClientRequest,
             .authenticating,
             .active,
             .error:
             throw SOCKSError.InvalidServerState()
        }
        
        if response.reply == .succeeded {
            self.state = .active
        } else {
            self.state = .error
        }
    }
    
    mutating func sendData() throws {
        switch self.state {
        case .authenticating:
            ()
        case .inactive,
             .waitingForClientGreeting,
             .waitingToSendAuthenticationMethod,
             .waitingForClientRequest,
             .waitingToSendResponse,
             .active,
             .error:
             throw SOCKSError.InvalidServerState()
        }
    }
    
    mutating func authenticationComplete() throws {
        switch self.state {
        case .authenticating:
            ()
        case .inactive,
             .waitingForClientGreeting,
             .waitingToSendAuthenticationMethod,
             .waitingForClientRequest,
             .waitingToSendResponse,
             .active,
             .error:
             throw SOCKSError.InvalidServerState()
        }
        
        self.state = .waitingForClientRequest
    }
}
