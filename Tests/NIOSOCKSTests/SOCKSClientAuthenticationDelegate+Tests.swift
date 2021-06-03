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
        XCTAssertEqual(delegate.status, .notStarted)
        XCTAssertNoThrow(try delegate.serverSelectedAuthenticationMethod(.noneRequired))
        XCTAssertEqual(delegate.status, .complete)
        
        // everything else should throw an error
        self.assertUnexpectedError(delegate: delegate, input: .gssapi)
        XCTAssertEqual(delegate.status, .failed)
        self.assertUnexpectedError(delegate: delegate, input: .noneAcceptable)
        XCTAssertEqual(delegate.status, .failed)
        self.assertUnexpectedError(delegate: delegate, input: .usernamePassword)
        XCTAssertEqual(delegate.status, .failed)
        self.assertUnexpectedError(delegate: delegate, input: .init(value: 123))
        XCTAssertEqual(delegate.status, .failed)
    }
    
    func testTypicalWorkflow() {
        let delegate = DefaultAuthenticationDelegate()
        XCTAssertNoThrow(try delegate.serverSelectedAuthenticationMethod(.noneRequired))
        
        // make sure no data is consumed by the default delegate
        var buffer = ByteBuffer(string: "hello")
        XCTAssertNoThrow(XCTAssertEqual(try delegate.handleIncomingData(buffer: &buffer), .authenticationComplete))
        XCTAssertEqual(String(buffer: buffer), "hello")
    }
    
}
