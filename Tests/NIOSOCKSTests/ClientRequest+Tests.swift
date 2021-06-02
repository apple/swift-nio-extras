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

public class ClientRequestTests: XCTestCase {
    
}

// MARK: - ClientRequest
extension ClientRequestTests {
    
    func testWriteClientRequest() {
        var buffer = ByteBuffer()
        XCTAssertTrue(buffer.readableBytes == 0)
        
        let req = ClientRequest(command: .connect, addressType: .ipv4([192, 168, 1, 1]), desiredPort: 80)
        XCTAssertEqual(buffer.writeClientRequest(req), 11)
        XCTAssertEqual(buffer.readableBytes, 10)
        XCTAssertEqual(buffer.readBytes(length: 10)!,
                       [0x05, 0x01, 0x00, 0x01, 0xC0, 0xA8, 0x01, 0x01, 0x00, 0x50])
    }
    
}

// MARK: - AddressType
extension ClientRequestTests {
    
    func testReadAddressType() {
        var ipv4 = ByteBuffer(bytes: [0x01, 0x10, 0x11, 0x12, 0x13])
        XCTAssertEqual(ipv4.readableBytes, 5)
        XCTAssertEqual(AddressType(buffer: &ipv4), .ipv4([0x10, 0x11, 0x12, 0x13]))
        XCTAssertEqual(ipv4.readableBytes, 0)
        
        var domain = ByteBuffer(bytes: [0x03, 0x04, 0x10, 0x11, 0x12, 0x13])
        XCTAssertEqual(domain.readableBytes, 6)
        XCTAssertEqual(AddressType(buffer: &domain), .domain([0x10, 0x11, 0x12, 0x13]))
        XCTAssertEqual(domain.readableBytes, 0)
        
        var ipv6 = ByteBuffer(bytes: [0x04, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])
        XCTAssertEqual(ipv6.readableBytes, 17)
        XCTAssertEqual(AddressType(buffer: &ipv6), .ipv6([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]))
        XCTAssertEqual(ipv6.readableBytes, 0)
        
    }
    
    func testWriteAddressType(){
        var ipv4 = ByteBuffer()
        XCTAssertEqual(ipv4.writeAddressType(.ipv4([192, 168, 1, 1])), 5)
        XCTAssertEqual(ipv4.readBytes(length: 5)!, [1, 192, 168, 1, 1])
        
        var domain = ByteBuffer()
        XCTAssertEqual(domain.writeAddressType(.domain([1, 2, 3, 4])), 6)
        XCTAssertEqual(domain.readBytes(length: 6)!, [3, 4, 1, 2, 3, 4])
        
        var ipv6 = ByteBuffer()
        XCTAssertEqual(ipv6.writeAddressType(.ipv6([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])), 17)
        XCTAssertEqual(ipv6.readBytes(length: 17)!, [4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])
    }
    
}
