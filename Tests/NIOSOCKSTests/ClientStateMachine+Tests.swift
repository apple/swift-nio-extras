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
@testable import NIOSOCKS
import XCTest

public class ClientStateMachineTests: XCTestCase {
 
    func testUsualWorkflow() {
        
        // create state machine and immediately send greeting
        var stateMachine = ClientStateMachine()
        XCTAssertNoThrow(try stateMachine.sendClientGreeting(.init(methods: [.noneRequired])))
        XCTAssertFalse(stateMachine.proxyEstablished)
        
        // provide the given server greeting, check what to do next
        var serverGreeting = ByteBuffer(bytes: [0x05, 0x00])
        XCTAssertNoThrow(XCTAssertEqual(try stateMachine.receiveBuffer(&serverGreeting), .authenticateIfNeeded(.noneRequired)))
        XCTAssertFalse(stateMachine.proxyEstablished)
        
        // finish authentication
        XCTAssertNoThrow(XCTAssertEqual(try stateMachine.authenticationComplete(), .sendRequest))
        XCTAssertFalse(stateMachine.proxyEstablished)
        
        // send the client request
        XCTAssertNoThrow(try stateMachine.sendClientRequest(.init(command: .bind, addressType: .init(address: try! .init(ipAddress: "192.168.1.1", port: 80)))))
        XCTAssertFalse(stateMachine.proxyEstablished)
        
        // recieve server response
        var serverResponse = ByteBuffer(bytes: [0x05, 0x00, 0x00, 0x01, 0x01, 0x02, 0x03, 0x04, 0x00, 0x50])
        XCTAssertNoThrow(XCTAssertEqual(try stateMachine.receiveBuffer(&serverResponse), .proxyEstablished))
        
        // proxy should be good to go
        XCTAssertTrue(stateMachine.proxyEstablished)
    }
    
}
