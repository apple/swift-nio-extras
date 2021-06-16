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
    
    init() {
        self.state = .inactive
    }
    
    func guardState(_ expected: ServerState) throws {
        try self.guardState([expected])
    }
    
    func guardState(_ expected: [ServerState]) throws {
        guard expected.contains(self.state) else {
            throw SOCKSError.InvalidServerState(expected: expected, actual: self.state)
        }
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
    
    mutating func handleClientGreeting(from buffer: inout ByteBuffer) throws -> ClientMessage? {
        return try buffer.parseUnwindingIfNeeded { buffer -> ClientMessage? in
            guard let greeting = try buffer.readClientGreeting() else {
                return nil
            }
            self.state = .waitingToSendAuthenticationMethod
            return .greeting(greeting)
        }
    }
    
    mutating func handleClientRequest(from buffer: inout ByteBuffer) throws -> ClientMessage? {
        return try buffer.parseUnwindingIfNeeded { buffer -> ClientMessage? in
            guard let request = try buffer.readClientRequest() else {
                return nil
            }
            self.state = .waitingToSendResponse
            return .request(request)
        }
    }
    
    mutating func handleAuthenticationData(from buffer: inout ByteBuffer) -> ClientMessage? {
        guard let buffer = buffer.readSlice(length: buffer.readableBytes) else {
            return nil
        }
        return .data(buffer)
    }
    
}

// MARK: - Outbound
extension ServerStateMachine {
    
    mutating func connectionEstablished() throws {
        try self.guardState(.inactive)
        self.state = .waitingForClientGreeting
    }
    
    mutating func sendAuthenticationMethod(_ method: SelectedAuthenticationMethod) throws {
        try self.guardState(.waitingToSendAuthenticationMethod)
        self.state = .authenticating
    }
    
    mutating func sendServerResponse(_ response: SOCKSResponse) throws {
        try self.guardState(.waitingToSendResponse)
        if response.reply == .succeeded {
            self.state = .active
        } else {
            self.state = .error
        }
    }
    
    mutating func sendData() throws {
        try self.guardState([.authenticating, .active])
    }
    
    mutating func authenticationComplete() throws {
        try self.guardState(.authenticating)
        self.state = .waitingForClientRequest
    }
}
