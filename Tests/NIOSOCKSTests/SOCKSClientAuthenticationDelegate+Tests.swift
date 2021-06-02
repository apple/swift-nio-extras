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

public class SOCKSClientAuthenticationClientTests: XCTestCase {

    func assertUnexpectedError(delegate: SOCKSClientAuthenticationDelegate, input: AuthenticationMethod) {
        XCTAssertThrowsError(try delegate.serverSelectedAuthenticationMethod(input)) { e in
            XCTAssertTrue(e is UnexpectedAuthenticationMethod)
        }
    }
    
    func testSelectedMethod() {
        let delegate = DefaultAuthenticationDelegate()
        
        // .noneRequired is valid
        XCTAssertNoThrow(XCTAssertEqual(try delegate.serverSelectedAuthenticationMethod(.noneRequired), .authenticationComplete))
        
        // everything else should throw an error
        self.assertUnexpectedError(delegate: delegate, input: .gssapi)
        self.assertUnexpectedError(delegate: delegate, input: .noneAcceptable)
        self.assertUnexpectedError(delegate: delegate, input: .usernamePassword)
        self.assertUnexpectedError(delegate: delegate, input: .init(value: 123))
    }
    
}
