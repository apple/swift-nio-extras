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

/// Sent by the client and received by the server.
public enum ClientMessage: Hashable, Sendable {

    /// Contains the proposed authentication methods.
    case greeting(ClientGreeting)

    /// Instructs the server of the target host, and the type of connection.
    case request(SOCKSRequest)

    /// Used to respond to server authentication challenges
    case authenticationData(ByteBuffer)
}

/// Sent by the server and received by the client.
public enum ServerMessage: Hashable, Sendable {

    /// Used by the server to instruct the client of the authentication method to use.
    case selectedAuthenticationMethod(SelectedAuthenticationMethod)

    /// Sent by the server to inform the client that establishing the proxy to the target
    /// host succeeded or failed.
    case response(SOCKSResponse)

    /// Used when authenticating to send server challenges to the client.
    case authenticationData(ByteBuffer, complete: Bool)
}

extension ByteBuffer {

    @discardableResult mutating func writeServerMessage(_ message: ServerMessage) -> Int {
        switch message {
        case .selectedAuthenticationMethod(let method):
            return self.writeMethodSelection(method)
        case .response(let response):
            return self.writeServerResponse(response)
        case .authenticationData(var buffer, _):
            return self.writeBuffer(&buffer)
        }
    }

}
