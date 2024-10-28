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

public class MethodSelectionTests: XCTestCase {

    func testReadFromByteBuffer() {
        var buffer = ByteBuffer(bytes: [0x05, 0x00])
        XCTAssertEqual(buffer.readableBytes, 2)
        XCTAssertNoThrow(XCTAssertEqual(try buffer.readMethodSelection(), .init(method: .noneRequired)))
        XCTAssertEqual(buffer.readableBytes, 0)
    }

    func testWriteToByteBuffer() {
        var buffer = ByteBuffer()
        XCTAssertEqual(buffer.writeMethodSelection(.init(method: .noneRequired)), 2)
        XCTAssertEqual(buffer, ByteBuffer(bytes: [0x05, 0x00]))
    }

}
