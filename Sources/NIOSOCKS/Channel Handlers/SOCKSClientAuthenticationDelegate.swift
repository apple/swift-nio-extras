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

public struct UnexpectedAuthenticationMethod: Error {
    public var expected: [AuthenticationMethod]
    public var actual: AuthenticationMethod
    
    public init(expected: [AuthenticationMethod], actual: AuthenticationMethod) {
        self.expected = expected
        self.actual = actual
    }
}

public enum AuthenticationResult: Hashable {
    case needsMoreData
    case respond(ByteBuffer)
    case authenticationFailed
    case authenticationComplete
}

public protocol SOCKSClientAuthenticationDelegate {
    
    var supportedAuthenticationMethods: [AuthenticationMethod] { get }
    
    /// Called when the SOCKS server has responded to the client's greeting
    /// and selected an authentication method. Note that this will only be called
    /// if the selected authentication mechanism requires some action. For example
    /// `.noneRequired` will not result in this function being called.
    /// - parameter method: The authentication method selected by the server.
    func serverSelectedAuthenticationMethod(_ method: AuthenticationMethod) throws -> AuthenticationResult
    
    /// Data received from the server is given to the delegate to process.
    /// The delegate can then decide to return data to the server if needed.
    /// - parameter buffer: The data received from the server
    /// - returns:
    func handleIncomingData(buffer: ByteBuffer) throws -> AuthenticationResult
    
}

/// Use if you're connecting to a server where you're confident that `.noneRequired` is a valid
/// authentication method.
public class DefaultAuthenticationDelegate: SOCKSClientAuthenticationDelegate {
    
    public let supportedAuthenticationMethods: [AuthenticationMethod] = [.noneRequired]
    
    public init() { }
    
    public func serverSelectedAuthenticationMethod(_ method: AuthenticationMethod) throws -> AuthenticationResult {
        guard method == .noneRequired else {
            throw UnexpectedAuthenticationMethod(expected: [.noneRequired], actual: method)
        }
        return .authenticationComplete
    }

    public func handleIncomingData(buffer: ByteBuffer) throws -> AuthenticationResult {
        fatalError("This should never be called and is a NIO failure.")
    }
}
