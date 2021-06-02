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

public class MethodSelection_Tests: XCTestCase {
 
    func testReadFromByteBuffer() {
        var buffer = ByteBuffer(bytes: [0x05, 0x00])
        XCTAssertEqual(buffer.readableBytes, 2)
        XCTAssertEqual(MethodSelection(buffer: &buffer), .init(method: .noneRequired))
        XCTAssertEqual(buffer.readableBytes, 0)
    }
    
}
