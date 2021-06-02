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

public class ClientGreeting_Tests: XCTestCase {
    
    func testInitFromBuffer() {
        var buffer = ByteBuffer()
        buffer.writeBytes([0x05, 0x01, 0x00])
        XCTAssertEqual(ClientGreeting(buffer: &buffer), .init(methods: [.noneRequired]))
        XCTAssertTrue(buffer.readableBytes == 0)
        
        buffer.writeBytes([0x05, 0x03, 0x00, 0x01, 0x02])
        XCTAssertEqual(ClientGreeting(buffer: &buffer), .init(methods: [.noneRequired, .gssAPI, .usernamePassword]))
        XCTAssertTrue(buffer.readableBytes == 0)
    }
    
    func testWriting() {
        
        var buffer = ByteBuffer()
        XCTAssertTrue(buffer.readableBytes == 0)
        
        let greeting = ClientGreeting(methods: [.noneRequired])
        XCTAssertTrue(buffer.writeClientGreeting(greeting) == 3)
        XCTAssertTrue(buffer.readableBytes == 3)
        XCTAssertTrue(buffer.readBytes(length: 3)! == [0x05, 0x01, 0x00])
    }
}
