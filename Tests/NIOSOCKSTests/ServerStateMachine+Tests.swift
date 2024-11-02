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

public class ServerStateMachineTests: XCTestCase {

    func testUsualWorkflow() {

        // create state machine and immediately connect
        var stateMachine = ServerStateMachine()
        XCTAssertNoThrow(try stateMachine.connectionEstablished())
        XCTAssertFalse(stateMachine.proxyEstablished)

        // send the client greeting
        var greeting = ByteBuffer(bytes: [0x05, 0x01, 0x00])
        XCTAssertNoThrow(try stateMachine.receiveBuffer(&greeting))
        XCTAssertFalse(stateMachine.proxyEstablished)

        // provide the given server greeting
        XCTAssertNoThrow(try stateMachine.sendAuthenticationMethod(.init(method: .noneRequired)))
        XCTAssertFalse(stateMachine.proxyEstablished)

        // send the client request
        var request = ByteBuffer(bytes: [0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
        XCTAssertNoThrow(try stateMachine.receiveBuffer(&request))
        XCTAssertFalse(stateMachine.proxyEstablished)

        // recieve server response
        let response = SOCKSResponse(reply: .succeeded, boundAddress: .domain("127.0.0.1", port: 80))
        XCTAssertNoThrow(try stateMachine.sendServerResponse(response))

        // proxy should be good to go
        XCTAssertTrue(stateMachine.proxyEstablished)
    }

    // Once an error occurs the state machine
    // should refuse to progress further, as
    // the connection should instead be closed.
    func testErrorsAreHandled() {

        // prepare the state machine
        var stateMachine = ServerStateMachine()
        var greeting = ByteBuffer(bytes: [0x05, 0x01, 0x00])
        XCTAssertNoThrow(try stateMachine.connectionEstablished())
        XCTAssertNoThrow(try stateMachine.receiveBuffer(&greeting))
        XCTAssertNoThrow(try stateMachine.sendAuthenticationMethod(.init(method: .noneRequired)))

        // write some invalid bytes from the client
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

    func testBytesArentConsumedOnError() {
        var stateMachine = ServerStateMachine()
        XCTAssertNoThrow(try stateMachine.connectionEstablished())
        var buffer = ByteBuffer(bytes: [0xFF, 0xFF])
        let copy = buffer
        XCTAssertThrowsError(try stateMachine.receiveBuffer(&buffer))
        XCTAssertEqual(buffer, copy)
    }
}
