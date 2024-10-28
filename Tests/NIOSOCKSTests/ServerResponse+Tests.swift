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

public class ServerResponseTests: XCTestCase {
}

// MARK: - ServeResponse
extension ServerResponseTests {

    func testServerResponseReadFromByteBuffer() {
        var buffer = ByteBuffer(bytes: [0x05, 0x00, 0x00, 0x01, 0x01, 0x02, 0x03, 0x04, 0x00, 0x50])
        XCTAssertEqual(buffer.readableBytes, 10)
        XCTAssertNoThrow(
            XCTAssertEqual(
                try buffer.readServerResponse(),
                .init(reply: .succeeded, boundAddress: .address(try! .init(ipAddress: "1.2.3.4", port: 80)))
            )
        )
        XCTAssertEqual(buffer.readableBytes, 0)
    }

}
