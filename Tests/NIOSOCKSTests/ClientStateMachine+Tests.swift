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
import XCTest

@testable import NIOSOCKS

public class ClientStateMachineTests: XCTestCase {

    func testUsualWorkflow() {

        // create state machine and immediately connect
        var stateMachine = ClientStateMachine()
        XCTAssertTrue(stateMachine.shouldBeginHandshake)
        XCTAssertNoThrow(XCTAssertEqual(try stateMachine.connectionEstablished(), .sendGreeting))
        XCTAssertFalse(stateMachine.proxyEstablished)

        // send the client greeting
        XCTAssertNoThrow(try stateMachine.sendClientGreeting(.init(methods: [.noneRequired])))
        XCTAssertFalse(stateMachine.shouldBeginHandshake)
        XCTAssertFalse(stateMachine.proxyEstablished)

        // provide the given server greeting, check what to do next
        var serverGreeting = ByteBuffer(bytes: [0x05, 0x00])
        XCTAssertNoThrow(XCTAssertEqual(try stateMachine.receiveBuffer(&serverGreeting), .sendRequest))
        XCTAssertFalse(stateMachine.shouldBeginHandshake)
        XCTAssertFalse(stateMachine.proxyEstablished)

        // finish authentication
        XCTAssertFalse(stateMachine.shouldBeginHandshake)
        XCTAssertFalse(stateMachine.proxyEstablished)

        // send the client request
        XCTAssertNoThrow(
            try stateMachine.sendClientRequest(
                .init(command: .bind, addressType: .address(try! .init(ipAddress: "192.168.1.1", port: 80)))
            )
        )
        XCTAssertFalse(stateMachine.shouldBeginHandshake)
        XCTAssertFalse(stateMachine.proxyEstablished)

        // recieve server response
        var serverResponse = ByteBuffer(bytes: [0x05, 0x00, 0x00, 0x01, 0x01, 0x02, 0x03, 0x04, 0x00, 0x50])
        XCTAssertNoThrow(XCTAssertEqual(try stateMachine.receiveBuffer(&serverResponse), .proxyEstablished))

        // proxy should be good to go
        XCTAssertFalse(stateMachine.shouldBeginHandshake)
        XCTAssertTrue(stateMachine.proxyEstablished)
    }

    // Once an error occurs the state machine
    // should refuse to progress further, as
    // the connection should instead be closed.
    func testErrorsAreHandled() {

        // prepare the state machine
        var stateMachine = ClientStateMachine()
        XCTAssertNoThrow(XCTAssertEqual(try stateMachine.connectionEstablished(), .sendGreeting))
        XCTAssertNoThrow(try stateMachine.sendClientGreeting(.init(methods: [.noneRequired])))

        // write some invalid bytes from the server
        // the state machine should throw
        var buffer = ByteBuffer(bytes: [0xFF, 0xFF])
        XCTAssertThrowsError(try stateMachine.receiveBuffer(&buffer)) { e in
            XCTAssertTrue(e is SOCKSError.InvalidProtocolVersion)
        }

        // Now write some valid bytes. This time
        // the state machine should throw an
        // UnexpectedRead, as we should have closed
        // the connection
        buffer = ByteBuffer(bytes: [0x05, 0x00])
        XCTAssertThrowsError(try stateMachine.receiveBuffer(&buffer)) { e in
            XCTAssertTrue(e is SOCKSError.UnexpectedRead)
        }
    }
}
