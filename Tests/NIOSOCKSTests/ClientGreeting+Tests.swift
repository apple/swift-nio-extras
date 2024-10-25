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

public class ClientGreetingTests: XCTestCase {

    func testInitFromBuffer() {
        var buffer = ByteBuffer()
        buffer.writeBytes([0x05, 0x01, 0x00])
        XCTAssertNoThrow(XCTAssertEqual(try buffer.readClientGreeting(), .init(methods: [.noneRequired])))
        XCTAssertEqual(buffer.readableBytes, 0)

        buffer.writeBytes([0x05, 0x03, 0x00, 0x01, 0x02])
        XCTAssertNoThrow(
            XCTAssertEqual(
                try buffer.readClientGreeting(),
                .init(methods: [.noneRequired, .gssapi, .usernamePassword])
            )
        )
        XCTAssertEqual(buffer.readableBytes, 0)
    }

    func testWriting() {
        var buffer = ByteBuffer()
        let greeting = ClientGreeting(methods: [.noneRequired])
        XCTAssertEqual(buffer.writeClientGreeting(greeting), 3)
        XCTAssertEqual(buffer.readableBytes, 3)
        XCTAssertEqual(buffer.readBytes(length: 3)!, [0x05, 0x01, 0x00])
    }
}
