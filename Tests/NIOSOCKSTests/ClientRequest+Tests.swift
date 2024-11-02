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

public class ClientRequestTests: XCTestCase {

}

// MARK: - SOCKSRequest
extension ClientRequestTests {

    func testWriteClientRequest() {
        var buffer = ByteBuffer()
        let req = SOCKSRequest(command: .connect, addressType: .address(try! .init(ipAddress: "192.168.1.1", port: 80)))
        XCTAssertEqual(buffer.writeClientRequest(req), 10)
        XCTAssertEqual(buffer.readableBytes, 10)
        XCTAssertEqual(
            buffer.readBytes(length: 10)!,
            [0x05, 0x01, 0x00, 1, 192, 168, 1, 1, 0x00, 0x50]
        )
    }

}

// MARK: - AddressType
extension ClientRequestTests {

    func testReadAddressType() {
        var ipv4 = ByteBuffer(bytes: [0x01, 0x0a, 0x0b, 0x0c, 0x0d, 0x00, 0x50])
        XCTAssertEqual(ipv4.readableBytes, 7)
        XCTAssertNoThrow(
            XCTAssertEqual(try ipv4.readAddressType(), .address(try! .init(ipAddress: "10.11.12.13", port: 80)))
        )
        XCTAssertEqual(ipv4.readableBytes, 0)

        var domain = ByteBuffer(bytes: [
            0x03, 0x0a, 0x67, 0x6f, 0x6f, 0x67, 0x6c, 0x65, 0x2e, 0x63, 0x6f, 0x6d, 0x00, 0x50,
        ])
        XCTAssertEqual(domain.readableBytes, 14)
        XCTAssertNoThrow(XCTAssertEqual(try domain.readAddressType(), .domain("google.com", port: 80)))
        XCTAssertEqual(domain.readableBytes, 0)

        var ipv6 = ByteBuffer(bytes: [
            0x04, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0xa0, 0x00,
            0x50,
        ])
        XCTAssertEqual(ipv6.readableBytes, 19)
        XCTAssertNoThrow(
            XCTAssertEqual(
                try ipv6.readAddressType(),
                .address(try! .init(ipAddress: "0102:0304:0506:0708:090a:0b0c:0d0e:0fa0", port: 80))
            )
        )
        XCTAssertEqual(ipv6.readableBytes, 0)

    }

    func testWriteAddressType() {
        var ipv4 = ByteBuffer()
        XCTAssertEqual(ipv4.writeAddressType(.address(try! .init(ipAddress: "192.168.1.1", port: 80))), 7)
        XCTAssertEqual(ipv4.readBytes(length: 5)!, [1, 192, 168, 1, 1])
        XCTAssertEqual(ipv4.readInteger(as: UInt16.self)!, 80)

        var ipv6 = ByteBuffer()
        XCTAssertEqual(
            ipv6.writeAddressType(.address(try! .init(ipAddress: "0001:0002:0003:0004:0005:0006:0007:0008", port: 80))),
            19
        )
        XCTAssertEqual(ipv6.readBytes(length: 17)!, [4, 0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7, 0, 8])
        XCTAssertEqual(ipv6.readInteger(as: UInt16.self)!, 80)

        var domain = ByteBuffer()
        XCTAssertEqual(domain.writeAddressType(.domain("127.0.0.1", port: 80)), 13)
        XCTAssertEqual(domain.readBytes(length: 11)!, [3, 9, 49, 50, 55, 46, 48, 46, 48, 46, 49])
        XCTAssertEqual(domain.readInteger(as: UInt16.self)!, 80)
    }

}
