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

fileprivate enum ClientState: Hashable {
    case ready
    case waitingForAuthenticationMethod(ClientGreeting)
    case waitingForClientRequest
    case waitingForServerResponse(ClientRequest)
    case active
}

enum ClientAction: Hashable {
    case none
    case sendRequest
    case proxyEstablished
}

public struct InvalidAuthenticationSelection: Error {
    
}

public struct ConnectionFailed: Error, Hashable {
    public var reply: Reply
}

struct ClientStateMachine {

    private var state: ClientState
    
    var proxyEstablished: Bool {
        switch self.state {
        case .active:
            return true
        case .ready, .waitingForAuthenticationMethod, .waitingForClientRequest, .waitingForServerResponse:
            return false
        }
    }
    
    init() {
        self.state = .ready
    }

    mutating func sendClientGreeting(_ greeting: ClientGreeting) {
        assert(self.state == .ready)
        self.state = .waitingForAuthenticationMethod(greeting)
    }
    
    mutating func sendClientRequest(_ request: ClientRequest) {
        assert(self.state == .waitingForClientRequest)
        self.state = .waitingForServerResponse(request)
    }
    
    // Returns `nil` if the buffer doesn't have enough data
    mutating func receiveBuffer(_ buffer: inout ByteBuffer) throws -> ClientAction? {
        switch self.state {
        case .waitingForAuthenticationMethod(let greeting):
            return try self.handleSelectedAuthenticationMethod(&buffer, greeting: greeting)
        case .waitingForServerResponse(let request):
            return try self.handleServerResponse(&buffer, request: request)
        default:
            preconditionFailure("Invalid state")
        }
    }
    
    mutating func handleSelectedAuthenticationMethod(_ buffer: inout ByteBuffer, greeting: ClientGreeting) throws -> ClientAction? {
        guard let selected = MethodSelection(buffer: &buffer) else {
            return nil
        }
        guard greeting.methods.contains(selected.method) else {
            throw InvalidAuthenticationSelection()
        }
        self.state = .waitingForClientRequest
        return .sendRequest
    }
    
    mutating func handleServerResponse(_ buffer: inout ByteBuffer, request: ClientRequest) throws -> ClientAction? {
        guard let response = try ServerResponse(buffer: &buffer) else {
            return nil
        }
        guard response.reply == .succeeded else {
            throw ConnectionFailed(reply: response.reply)
        }
        self.state = .active
        return .proxyEstablished
    }
    
}
