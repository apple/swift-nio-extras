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

public class ServerResponseTests: XCTestCase {
}

// MARK: - ServeResponse
extension ServerResponse_Tests {
    
    func testServerResponseReadFromByteBuffer() {
        var buffer = ByteBuffer(bytes: [0x05, 0x00, 0x00, 0x01, 0x01, 0x02, 0x03, 0x04, 0x00, 0x50])
        XCTAssertEqual(buffer.readableBytes, 10)
        XCTAssertEqual(ServerResponse(buffer: &buffer), .init(reply: .succeeded, boundAddress: .ipv4([1, 2, 3, 4]), boundPort: 80))
        XCTAssertEqual(buffer.readableBytes, 0)
    }
    
}
