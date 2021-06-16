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

/// Sent by the client and received by the server.
public enum ClientMessage: Hashable {
    
    /// Contains the proposed authentication methods.
    case greeting(ClientGreeting)
    
    /// Instructs the server of the target host, and the type of connection.
    case request(SOCKSRequest)
    
    /// Data that is sent once the handshake is complete. Handling this case
    /// should be rare, as you should remove the server handler after the handshake
    /// process is complete. It can also be used when authenticating in response
    /// to server challenges.
    case data(ByteBuffer)
}

/// Sent by the server and received by the client.
public enum ServerMessage: Hashable {
    
    /// Used by the server to instruct the client of the authentication method to use.
    case selectedAuthenticationMethod(SelectedAuthenticationMethod)
    
    /// Sent by the server to inform the client that establishing the proxy to the target
    /// host succeeded or failed.
    case response(SOCKSResponse)
    
    /// Typically used when authenticating to send server challenges to the client.
    case data(ByteBuffer)
    
    /// This is a faux message to update the server's state machine. It should be sent
    /// once the server is satisified that the client is fully-authenticated.
    case authenticationComplete
}

extension ByteBuffer {
    
    @discardableResult mutating func writeServerMessage(_ message: ServerMessage) -> Int {
        switch message {
        case .selectedAuthenticationMethod(let method):
            return self.writeMethodSelection(method)
        case .response(let response):
            return self.writeServerResponse(response)
        case .data(var buffer):
            return self.writeBuffer(&buffer)
        case .authenticationComplete:
            return 0
        }
    }
    
}
