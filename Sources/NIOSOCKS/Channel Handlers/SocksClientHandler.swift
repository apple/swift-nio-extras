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

public class SocksClientHandler: ChannelDuplexHandler {
    
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    
    let supportedAuthenticationMethods: [AuthenticationMethod]
    
    public init(supportedAuthenticationMethods: [AuthenticationMethod]) {
        precondition(supportedAuthenticationMethods.count <= 255)
        self.supportedAuthenticationMethods = supportedAuthenticationMethods
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        print("inactive")
        context.fireChannelInactive()
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        print("active")
        let greeting = ClientGreeting(
            version: 5,
            methods: self.supportedAuthenticationMethods
        )
        var buffer = ByteBuffer()
        buffer.writeClientGreeting(greeting)
        print(buffer.debugDescription)
        context.write(self.wrapOutboundOut(buffer)).whenComplete { r in
            print(r)
        }
    }
    
}
