//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2026 Apple Inc. and the SwiftNIO project authors
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

public class UsernamePasswordTests: XCTestCase {

    // MARK: Credentials

    func testCredentialsAcceptLimits() {
        XCTAssertNoThrow(try UsernamePasswordCredentials(username: "u", password: "p"))
        // an empty password is fine (curl sends one for `socks5://user@host`), an empty username is not
        XCTAssertNoThrow(try UsernamePasswordCredentials(username: "u", password: ""))
        XCTAssertNoThrow(
            try UsernamePasswordCredentials(
                username: String(repeating: "u", count: 255),
                password: String(repeating: "p", count: 255)
            )
        )
    }

    func testCredentialsRejectEmptyAndOverlongValues() {
        func assertInvalid(
            username: String,
            password: String,
            field: SOCKSError.InvalidCredentialLength.Field,
            actual: Int,
            line: UInt = #line
        ) {
            XCTAssertThrowsError(try UsernamePasswordCredentials(username: username, password: password), line: line) {
                XCTAssertEqual(
                    $0 as? SOCKSError.InvalidCredentialLength,
                    .init(field: field, actual: actual),
                    line: line
                )
            }
        }
        let ok = "x"
        assertInvalid(username: "", password: ok, field: .username, actual: 0)
        assertInvalid(username: String(repeating: "u", count: 256), password: ok, field: .username, actual: 256)
        assertInvalid(username: ok, password: String(repeating: "p", count: 256), field: .password, actual: 256)
    }

    func testCredentialsFromBytes() throws {
        let credentials = try UsernamePasswordCredentials(usernameBytes: [0xFF, 0x61], passwordBytes: [])
        XCTAssertEqual(credentials.usernameBytes, [0xFF, 0x61])
        XCTAssertEqual(credentials.passwordBytes, [])

        XCTAssertThrowsError(try UsernamePasswordCredentials(usernameBytes: [], passwordBytes: [1])) {
            XCTAssertEqual($0 as? SOCKSError.InvalidCredentialLength, .init(field: .username, actual: 0))
        }
        XCTAssertThrowsError(
            try UsernamePasswordCredentials(usernameBytes: [1], passwordBytes: .init(repeating: 0xFF, count: 256))
        ) {
            XCTAssertEqual($0 as? SOCKSError.InvalidCredentialLength, .init(field: .password, actual: 256))
        }
        XCTAssertNoThrow(
            try UsernamePasswordCredentials(
                usernameBytes: .init(repeating: 0xFF, count: 255),
                passwordBytes: .init(repeating: 0xFF, count: 255)
            )
        )
    }

    func testCredentialsCompareTheExactBytes() throws {
        // different bytes must never be equal, even if they decode to the same (lossy) string
        let ff = try UsernamePasswordCredentials(usernameBytes: [0xFF], passwordBytes: [1])
        let fe = try UsernamePasswordCredentials(usernameBytes: [0xFE], passwordBytes: [1])
        XCTAssertEqual(ff.username, fe.username)
        XCTAssertNotEqual(ff, fe)
        XCTAssertEqual(Set([ff, fe]).count, 2)

        // canonically equivalent strings are different byte sequences
        let precomposed = try UsernamePasswordCredentials(username: "u", password: "\u{e9}")
        let decomposed = try UsernamePasswordCredentials(username: "u", password: "e\u{301}")
        XCTAssertNotEqual(precomposed, decomposed)
        XCTAssertEqual(precomposed.passwordBytes, [0xC3, 0xA9])
        XCTAssertEqual(decomposed.passwordBytes, [0x65, 0xCC, 0x81])
    }

    func testCredentialLimitsAreCountedInBytesNotCharacters() {
        // "é" is 2 bytes in UTF-8: 128 characters are 256 bytes
        XCTAssertThrowsError(
            try UsernamePasswordCredentials(username: String(repeating: "é", count: 128), password: "p")
        )
        XCTAssertNoThrow(try UsernamePasswordCredentials(username: String(repeating: "é", count: 127), password: "p"))
    }

    func testDescriptionsAndDumpsDoNotLeakThePassword() throws {
        let credentials = try UsernamePasswordCredentials(username: "alice", password: "hunter2")
        let request = UsernamePasswordRequest(credentials: credentials)

        var credentialsDump = ""
        dump(credentials, to: &credentialsDump)
        var requestDump = ""
        dump(request, to: &requestDump)
        var arrayDump = ""
        dump([request], to: &arrayDump)

        for text in [
            "\(credentials)", String(reflecting: credentials), "\(request)", String(reflecting: request),
            credentialsDump, requestDump, arrayDump,
        ] {
            XCTAssertTrue(text.contains("alice"), text)
            XCTAssertFalse(text.contains("hunter2"), text)
            // nor the raw bytes of the password
            XCTAssertFalse(text.contains("104"), text)
            XCTAssertFalse(text.contains("0x68"), text)
        }
        XCTAssertTrue(credentialsDump.contains("<redacted>"), credentialsDump)
        XCTAssertTrue(requestDump.contains("<redacted>"), requestDump)

        // the password is still readable by those that need it
        XCTAssertEqual(credentials.password, "hunter2")
        XCTAssertEqual(credentials.passwordBytes, Array("hunter2".utf8))
    }

    // MARK: Request

    func testWriteRequest() throws {
        var buffer = ByteBuffer()
        let request = UsernamePasswordRequest(credentials: try .init(username: "ab", password: "cde"))
        XCTAssertEqual(buffer.writeUsernamePasswordRequest(request), 8)
        XCTAssertEqual(buffer, ByteBuffer(bytes: [0x01, 0x02, 0x61, 0x62, 0x03, 0x63, 0x64, 0x65]))
    }

    func testReadRequest() throws {
        var buffer = ByteBuffer(bytes: [0x01, 0x02, 0x61, 0x62, 0x03, 0x63, 0x64, 0x65])
        let request = try XCTUnwrap(try buffer.readUsernamePasswordRequest())
        XCTAssertEqual(request, UsernamePasswordRequest(credentials: try .init(username: "ab", password: "cde")))
        XCTAssertEqual(buffer.readableBytes, 0)
    }

    func testWriteRequestWithEmptyPassword() throws {
        var buffer = ByteBuffer()
        let request = UsernamePasswordRequest(credentials: try .init(username: "ab", password: ""))
        XCTAssertEqual(buffer.writeUsernamePasswordRequest(request), 5)
        XCTAssertEqual(buffer, ByteBuffer(bytes: [0x01, 0x02, 0x61, 0x62, 0x00]))
        XCTAssertEqual(try buffer.readUsernamePasswordRequest(), request)
    }

    func testRequestWithNonASCIIRoundTrips() throws {
        let request = UsernamePasswordRequest(credentials: try .init(username: "\u{e9}", password: "\u{f1}\u{1F600}"))
        var buffer = ByteBuffer()
        XCTAssertEqual(buffer.writeUsernamePasswordRequest(request), 1 + 1 + 2 + 1 + 6)
        XCTAssertEqual(
            buffer,
            ByteBuffer(bytes: [0x01, 0x02, 0xC3, 0xA9, 0x06, 0xC3, 0xB1, 0xF0, 0x9F, 0x98, 0x80])
        )
        let read = try XCTUnwrap(try buffer.readUsernamePasswordRequest())
        XCTAssertEqual(read, request)
        XCTAssertEqual(read.username, "\u{e9}")
        XCTAssertEqual(read.password, "\u{f1}\u{1F600}")
    }

    func testRequestWithInvalidUTF8KeepsTheExactBytesAndCanBeWrittenAgain() throws {
        // the worst case for a lossy decoding: every byte would turn into a 3 byte U+FFFD
        let wire: [UInt8] = [0x01, 0xFF] + [UInt8](repeating: 0xFF, count: 255) + [0x01, 0x61]
        var buffer = ByteBuffer(bytes: wire)
        let request = try XCTUnwrap(try buffer.readUsernamePasswordRequest())
        XCTAssertEqual(buffer.readableBytes, 0)
        XCTAssertEqual(request.credentials.usernameBytes, [UInt8](repeating: 0xFF, count: 255))
        XCTAssertEqual(request.credentials.passwordBytes, [0x61])

        // writing it back must not trap and must reproduce the bytes
        var again = ByteBuffer()
        XCTAssertEqual(again.writeUsernamePasswordRequest(request), wire.count)
        XCTAssertEqual(again, ByteBuffer(bytes: wire))
    }

    func testRequestRoundTripAtTheLimit() throws {
        let credentials = try UsernamePasswordCredentials(
            username: String(repeating: "u", count: 255),
            password: String(repeating: "p", count: 255)
        )
        var buffer = ByteBuffer()
        XCTAssertEqual(buffer.writeUsernamePasswordRequest(.init(credentials: credentials)), 3 + 255 + 255)
        XCTAssertEqual(try buffer.readUsernamePasswordRequest()?.credentials, credentials)
    }

    func testReadIncompleteRequestIsUnwound() throws {
        let bytes: [UInt8] = [0x01, 0x02, 0x61, 0x62, 0x03, 0x63, 0x64, 0x65]
        for count in 0..<bytes.count {
            var buffer = ByteBuffer(bytes: Array(bytes[..<count]))
            XCTAssertNoThrow(XCTAssertNil(try buffer.readUsernamePasswordRequest()), "\(count) bytes")
            XCTAssertEqual(buffer.readableBytes, count)
        }
    }

    func testReadRequestRejectsBadVersion() {
        var wrongVersion = ByteBuffer(bytes: [0x05, 0x01, 0x61, 0x01, 0x62])
        XCTAssertThrowsError(try wrongVersion.readUsernamePasswordRequest()) {
            XCTAssertEqual($0 as? SOCKSError.InvalidSubnegotiationVersion, .init(actual: 0x05))
        }
        XCTAssertEqual(wrongVersion.readableBytes, 5)
    }

    func testReadRequestIsLenientWithEmptyFields() throws {
        // RFC 1929 wants at least one byte, but it's up to a server to decide what to do with it
        var emptyUsername = ByteBuffer(bytes: [0x01, 0x00, 0x01, 0x62])
        let first = try XCTUnwrap(try emptyUsername.readUsernamePasswordRequest())
        XCTAssertEqual(first.credentials.usernameBytes, [])
        XCTAssertEqual(first.credentials.passwordBytes, [0x62])

        var emptyPassword = ByteBuffer(bytes: [0x01, 0x01, 0x61, 0x00])
        let second = try XCTUnwrap(try emptyPassword.readUsernamePasswordRequest())
        XCTAssertEqual(second.credentials.usernameBytes, [0x61])
        XCTAssertEqual(second.credentials.passwordBytes, [])

        var bothEmpty = ByteBuffer(bytes: [0x01, 0x00, 0x00])
        let third = try XCTUnwrap(try bothEmpty.readUsernamePasswordRequest())
        XCTAssertEqual(third.credentials.usernameBytes, [])
        XCTAssertEqual(third.credentials.passwordBytes, [])

        // and they can be written back
        var buffer = ByteBuffer()
        buffer.writeUsernamePasswordRequest(third)
        XCTAssertEqual(buffer, ByteBuffer(bytes: [0x01, 0x00, 0x00]))
    }

    // MARK: Response

    func testWriteResponse() {
        var buffer = ByteBuffer()
        XCTAssertEqual(buffer.writeUsernamePasswordResponse(.success), 2)
        XCTAssertEqual(buffer.writeUsernamePasswordResponse(.init(status: 0x42)), 2)
        XCTAssertEqual(buffer, ByteBuffer(bytes: [0x01, 0x00, 0x01, 0x42]))
    }

    func testReadResponse() {
        var buffer = ByteBuffer(bytes: [0x01, 0x00, 0x01, 0x01])
        XCTAssertNoThrow(XCTAssertEqual(try buffer.readUsernamePasswordResponse(), .success))
        XCTAssertNoThrow(XCTAssertEqual(try buffer.readUsernamePasswordResponse(), .failure))
        XCTAssertEqual(buffer.readableBytes, 0)
        XCTAssertTrue(UsernamePasswordResponse.success.isSuccess)
        XCTAssertFalse(UsernamePasswordResponse.failure.isSuccess)
        XCTAssertFalse(UsernamePasswordResponse(status: 0xFF).isSuccess)
    }

    func testReadIncompleteResponseIsUnwound() {
        var buffer = ByteBuffer(bytes: [0x01])
        XCTAssertNoThrow(XCTAssertNil(try buffer.readUsernamePasswordResponse()))
        XCTAssertEqual(buffer.readableBytes, 1)
    }

    func testReadResponseRejectsBadVersion() {
        var buffer = ByteBuffer(bytes: [0x05, 0x00])
        XCTAssertThrowsError(try buffer.readUsernamePasswordResponse()) {
            XCTAssertEqual($0 as? SOCKSError.InvalidSubnegotiationVersion, .init(actual: 0x05))
        }
        XCTAssertEqual(buffer.readableBytes, 2)
    }

}
