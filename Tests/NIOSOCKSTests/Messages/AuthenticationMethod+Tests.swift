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

public class AuthenticationMethod_Tests: XCTestCase {
    
    // prevent accidental regression of the built-in auth methods
    func testStaticVarsAreCorrect() {
        XCTAssertEqual(AuthenticationMethod.noneRequired.value, 0x00)
        XCTAssertEqual(AuthenticationMethod.gssAPI.value, 0x01)
        XCTAssertEqual(AuthenticationMethod.usernamePassword.value, 0x02)
        XCTAssertEqual(AuthenticationMethod.noneAcceptable.value, 0xFF)
    }
}
