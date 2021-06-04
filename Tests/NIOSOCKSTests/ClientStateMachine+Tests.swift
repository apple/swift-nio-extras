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
        
        // create state machine and immediately connect
        var stateMachine = ClientStateMachine(authenticationDelegate: DefaultAuthenticationDelegate())
        XCTAssertTrue(stateMachine.shouldBeginHandshake)
        XCTAssertEqual(stateMachine.connectionEstablished(), .sendGreeting)
        XCTAssertFalse(stateMachine.proxyEstablished)
        
        // send the client greeting
        stateMachine.sendClientGreeting(.init(methods: [.noneRequired]))
        XCTAssertFalse(stateMachine.shouldBeginHandshake)
        XCTAssertFalse(stateMachine.proxyEstablished)
        
        // provide the given server greeting, check what to do next
        var serverGreeting = ByteBuffer(bytes: [0x05, 0x00])
        XCTAssertNoThrow(XCTAssertEqual(try stateMachine.receiveBuffer(&serverGreeting), .action(.sendRequest)))
        XCTAssertFalse(stateMachine.shouldBeginHandshake)
        XCTAssertFalse(stateMachine.proxyEstablished)
        
        // finish authentication
        XCTAssertFalse(stateMachine.shouldBeginHandshake)
        XCTAssertFalse(stateMachine.proxyEstablished)
        
        // send the client request
        stateMachine.sendClientRequest(.init(command: .bind, addressType: .address(try! .init(ipAddress: "192.168.1.1", port: 80))))
        XCTAssertFalse(stateMachine.shouldBeginHandshake)
        XCTAssertFalse(stateMachine.proxyEstablished)
        
        // recieve server response
        var serverResponse = ByteBuffer(bytes: [0x05, 0x00, 0x00, 0x01, 0x01, 0x02, 0x03, 0x04, 0x00, 0x50])
        XCTAssertNoThrow(XCTAssertEqual(try stateMachine.receiveBuffer(&serverResponse), .action(.proxyEstablished)))
        
        // proxy should be good to go
        XCTAssertFalse(stateMachine.shouldBeginHandshake)
        XCTAssertTrue(stateMachine.proxyEstablished)
    }
    
    // Use a mock authentication delegate that waits until it
    // recieves the byte 0x05 from the server, at which point
    // authentication has succeeded. Also tests drip feeding.
    // 0xAA is our special secret test auth method.
    func testAuthenticationFlow() {
        
        class MockDelegate: SOCKSClientAuthenticationDelegate {
            var supportedAuthenticationMethods: [AuthenticationMethod] = [.init(value: 0xAA)]
            
            var status: AuthenticationStatus = .notStarted
            
            func serverSelectedAuthenticationMethod(_ method: AuthenticationMethod) throws {
                
            }
            
            func handleIncomingData(buffer: inout ByteBuffer) throws -> AuthenticationResult {
                guard let byte = buffer.readInteger(as: UInt8.self) else {
                    return .needsMoreData
                }
                switch byte {
                case 0x05:
                    return .authenticationComplete
                default:
                    return .respond(.init(bytes: [byte]))
                }
            }
        }
        
        var stateMachine = ClientStateMachine(authenticationDelegate: MockDelegate())
        XCTAssertEqual(stateMachine.connectionEstablished(), .sendGreeting)
        stateMachine.sendClientGreeting(.init(methods: [.init(value: 0xAA)]))
        
        // Server responds with the selected auth method.
        // Auth should now begin, but we have no data
        // so we should receive a "wait" action.
        var serverGreetingBuffer = ByteBuffer(bytes: [0x05, 0xAA])
        XCTAssertNoThrow(XCTAssertEqual(try stateMachine.receiveBuffer(&serverGreetingBuffer), .waitForMoreData))
        
        // Alright let's drip feed in a few bytes
        // We're expecting the mock delegate to just
        // return them.
        func assertReceivedBuffer(_ buffer: ByteBuffer, line: UInt = #line) {
            do {
                var rBuffer = buffer
                switch try stateMachine.receiveBuffer(&rBuffer) {
                case .action(.sendData(let data)):
                    XCTAssertEqual(data, buffer, line: line)
                    XCTAssertEqual(rBuffer.readableBytes, 0)
                default:
                    XCTFail(line: line)
                }
            } catch {
                XCTFail("\(error)", line: line)
            }
        }
        assertReceivedBuffer(ByteBuffer(bytes: [0x00]))
        assertReceivedBuffer(ByteBuffer(bytes: [0x01]))
        assertReceivedBuffer(ByteBuffer(bytes: [0x02]))
        assertReceivedBuffer(ByteBuffer(bytes: [0x03]))
        assertReceivedBuffer(ByteBuffer(bytes: [0x04]))
        
        // Now send nothing, we should be told that we need more data
        var emptyBuffer = ByteBuffer()
        XCTAssertNoThrow(XCTAssertEqual(try stateMachine.receiveBuffer(&emptyBuffer), .waitForMoreData))
        
        // With this special 0x05 byte we should see the authentication complete.
        // So now we should be told to send the client request.
        // Business as usual from here.
        var finalAuthByte = ByteBuffer(bytes: [0x05])
        XCTAssertNoThrow(XCTAssertEqual(try stateMachine.receiveBuffer(&finalAuthByte), .action(.sendRequest)))
    }
    
    // Once an error occurs the state machine
    // should refuse to progress further, as
    // the connection should instead be closed.
    func testErrorsAreHandled() {
        
        // prepare the state machine
        var stateMachine = ClientStateMachine(authenticationDelegate: DefaultAuthenticationDelegate())
        XCTAssertEqual(stateMachine.connectionEstablished(), .sendGreeting)
        stateMachine.sendClientGreeting(.init(methods: [.noneRequired]))
        
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
