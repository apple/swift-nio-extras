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

public class HelperTests: XCTestCase {

    // Returning nil should unwind the changes
    func testUnwindingReturnNil() {
        var buffer = ByteBuffer(bytes: [1, 2, 3, 4, 5])
        XCTAssertNil(
            buffer.parseUnwindingIfNeeded { buffer -> Int? in
                XCTAssertEqual(buffer.readBytes(length: 5), [1, 2, 3, 4, 5])
                return nil
            }
        )
        XCTAssertEqual(buffer, ByteBuffer(bytes: [1, 2, 3, 4, 5]))
    }

    func testUnwindingThrowError() {

        struct TestError: Error, Hashable {}

        var buffer = ByteBuffer(bytes: [1, 2, 3, 4, 5])
        XCTAssertThrowsError(
            try buffer.parseUnwindingIfNeeded { buffer -> Int? in
                XCTAssertEqual(buffer.readBytes(length: 5), [1, 2, 3, 4, 5])
                throw TestError()
            }
        ) { e in
            XCTAssertEqual(e as? TestError, TestError())
        }
        XCTAssertEqual(buffer, ByteBuffer(bytes: [1, 2, 3, 4, 5]))
    }

    // If we don't return nil and don't throw an error then all should be good
    func testUnwindingNotRequired() {
        var buffer = ByteBuffer(bytes: [1, 2, 3, 4, 5])
        buffer.parseUnwindingIfNeeded { buffer in
            XCTAssertEqual(buffer.readBytes(length: 5), [1, 2, 3, 4, 5])
        }
        XCTAssertEqual(buffer, ByteBuffer(bytes: []))
    }

}
