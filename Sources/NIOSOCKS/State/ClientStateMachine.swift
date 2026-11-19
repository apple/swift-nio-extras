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

import NIOCore

private enum ClientState: Hashable {
    case inactive
    case waitingForClientGreeting
    case waitingForAuthenticationMethod(ClientGreeting)
    case waitingToSendCredentials
    case waitingForCredentialsResponse
    case waitingForClientRequest
    case waitingForServerResponse(SOCKSRequest)
    case active
    case error
}

enum ClientAction: Hashable {
    case waitForMoreData
    case sendGreeting
    case sendCredentials
    case sendRequest
    case proxyEstablished
}

struct ClientStateMachine {

    private var state: ClientState

    var proxyEstablished: Bool {
        switch self.state {
        case .active:
            return true
        case .error, .inactive, .waitingForAuthenticationMethod, .waitingForClientGreeting, .waitingForClientRequest,
            .waitingForServerResponse, .waitingToSendCredentials, .waitingForCredentialsResponse:
            return false
        }
    }

    var shouldBeginHandshake: Bool {
        switch self.state {
        case .inactive:
            return true
        case .active, .error, .waitingForAuthenticationMethod, .waitingForClientGreeting, .waitingForClientRequest,
            .waitingForServerResponse, .waitingToSendCredentials, .waitingForCredentialsResponse:
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
                guard let action = try self.handleSelectedAuthenticationMethod(&buffer, greeting: greeting) else {
                    return .waitForMoreData
                }
                return action
            case .waitingForCredentialsResponse:
                guard let action = try self.handleCredentialsResponse(&buffer) else {
                    return .waitForMoreData
                }
                return action
            case .waitingForServerResponse(let request):
                guard let action = try self.handleServerResponse(&buffer, request: request) else {
                    return .waitForMoreData
                }
                return action
            case .active, .error, .inactive, .waitingForClientGreeting, .waitingForClientRequest,
                .waitingToSendCredentials:
                throw SOCKSError.UnexpectedRead()
            }
        } catch {
            self.state = .error
            throw error
        }
    }

    mutating func handleSelectedAuthenticationMethod(
        _ buffer: inout ByteBuffer,
        greeting: ClientGreeting
    ) throws -> ClientAction? {
        try buffer.parseUnwindingIfNeeded { buffer -> ClientAction? in
            guard let selected = try buffer.readMethodSelection() else {
                return nil
            }
            // RFC 1928: the server has no acceptable method, the connection has to be closed.
            guard selected.method != .noneAcceptable else {
                throw SOCKSError.NoValidAuthenticationMethod()
            }
            guard greeting.methods.contains(selected.method) else {
                throw SOCKSError.InvalidAuthenticationSelection(selection: selected.method)
            }

            return try self.authenticate(&buffer, method: selected.method)
        }
    }

    mutating func handleCredentialsResponse(_ buffer: inout ByteBuffer) throws -> ClientAction? {
        try buffer.parseUnwindingIfNeeded { buffer -> ClientAction? in
            guard let response = try buffer.readUsernamePasswordResponse() else {
                return nil
            }
            guard response.isSuccess else {
                throw SOCKSError.AuthenticationFailed(status: response.status)
            }
            self.state = .waitingForClientRequest
            return .sendRequest
        }
    }

    mutating func handleServerResponse(_ buffer: inout ByteBuffer, request: SOCKSRequest) throws -> ClientAction? {
        try buffer.parseUnwindingIfNeeded { buffer -> ClientAction? in
            guard let response = try buffer.readServerResponse() else {
                return nil
            }
            guard response.reply == .succeeded else {
                throw SOCKSError.ConnectionFailed(reply: response.reply)
            }
            self.state = .active
            return .proxyEstablished
        }
    }

    mutating func authenticate(_ buffer: inout ByteBuffer, method: AuthenticationMethod) throws -> ClientAction {
        switch method {
        case .noneRequired:
            // nothing to negotiate, instruct the client to send the request
            self.state = .waitingForClientRequest
            return .sendRequest
        case .usernamePassword:
            // RFC 1929 sub-negotiation, the request has to be sent before the connect request
            self.state = .waitingToSendCredentials
            return .sendCredentials
        case .noneAcceptable:
            throw SOCKSError.NoValidAuthenticationMethod()
        default:
            // e.g. GSSAPI, which is not implemented
            throw SOCKSError.UnsupportedAuthenticationMethod(method: method)
        }
    }

}

// MARK: - Outgoing
extension ClientStateMachine {

    mutating func connectionEstablished() throws -> ClientAction {
        guard self.state == .inactive else {
            throw SOCKSError.InvalidClientState()
        }
        self.state = .waitingForClientGreeting
        return .sendGreeting
    }

    mutating func sendClientGreeting(_ greeting: ClientGreeting) throws {
        guard self.state == .waitingForClientGreeting else {
            throw SOCKSError.InvalidClientState()
        }
        self.state = .waitingForAuthenticationMethod(greeting)
    }

    mutating func sendClientCredentials() throws {
        guard self.state == .waitingToSendCredentials else {
            throw SOCKSError.InvalidClientState()
        }
        self.state = .waitingForCredentialsResponse
    }

    mutating func sendClientRequest(_ request: SOCKSRequest) throws {
        guard self.state == .waitingForClientRequest else {
            throw SOCKSError.InvalidClientState()
        }
        self.state = .waitingForServerResponse(request)
    }

}
