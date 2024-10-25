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
    case waitingForClientRequest
    case waitingForServerResponse(SOCKSRequest)
    case active
    case error
}

enum ClientAction: Hashable {
    case waitForMoreData
    case sendGreeting
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
            .waitingForServerResponse:
            return false
        }
    }

    var shouldBeginHandshake: Bool {
        switch self.state {
        case .inactive:
            return true
        case .active, .error, .waitingForAuthenticationMethod, .waitingForClientGreeting, .waitingForClientRequest,
            .waitingForServerResponse:
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
            case .waitingForServerResponse(let request):
                guard let action = try self.handleServerResponse(&buffer, request: request) else {
                    return .waitForMoreData
                }
                return action
            case .active, .error, .inactive, .waitingForClientGreeting, .waitingForClientRequest:
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
            guard greeting.methods.contains(selected.method) else {
                throw SOCKSError.InvalidAuthenticationSelection(selection: selected.method)
            }

            // we don't current support any form of authentication
            return self.authenticate(&buffer, method: selected.method)
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

    mutating func authenticate(_ buffer: inout ByteBuffer, method: AuthenticationMethod) -> ClientAction {
        precondition(method == .noneRequired, "No authentication mechanism is supported. Use .noneRequired only.")

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

    mutating func sendClientRequest(_ request: SOCKSRequest) throws {
        guard self.state == .waitingForClientRequest else {
            throw SOCKSError.InvalidClientState()
        }
        self.state = .waitingForServerResponse(request)
    }

}
