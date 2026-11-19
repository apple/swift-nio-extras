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
import NIOEmbedded
import XCTest

@testable import NIOSOCKS

// MARK: - State machines

public class UsernamePasswordStateMachineTests: XCTestCase {

    private func clientStateMachineAwaitingMethod(offering methods: [AuthenticationMethod]) throws -> ClientStateMachine
    {
        var stateMachine = ClientStateMachine()
        XCTAssertEqual(try stateMachine.connectionEstablished(), .sendGreeting)
        try stateMachine.sendClientGreeting(.init(methods: methods))
        return stateMachine
    }

    func testClientUsernamePasswordWorkflow() throws {
        var stateMachine = try self.clientStateMachineAwaitingMethod(offering: [.noneRequired, .usernamePassword])

        var selection = ByteBuffer(bytes: [0x05, 0x02])
        XCTAssertEqual(try stateMachine.receiveBuffer(&selection), .sendCredentials)
        XCTAssertFalse(stateMachine.proxyEstablished)

        // credentials have to be sent before anything else
        XCTAssertThrowsError(
            try stateMachine.sendClientRequest(.init(command: .connect, addressType: .domain("a", port: 1)))
        ) {
            XCTAssertTrue($0 is SOCKSError.InvalidClientState)
        }
        try stateMachine.sendClientCredentials()

        var status = ByteBuffer(bytes: [0x01, 0x00])
        XCTAssertEqual(try stateMachine.receiveBuffer(&status), .sendRequest)
        XCTAssertFalse(stateMachine.proxyEstablished)

        try stateMachine.sendClientRequest(.init(command: .connect, addressType: .domain("a", port: 1)))
        var response = ByteBuffer(bytes: [0x05, 0x00, 0x00, 0x01, 1, 2, 3, 4, 0x00, 0x50])
        XCTAssertEqual(try stateMachine.receiveBuffer(&response), .proxyEstablished)
        XCTAssertTrue(stateMachine.proxyEstablished)
    }

    func testClientWaitsForTheWholeStatusResponse() throws {
        var stateMachine = try self.clientStateMachineAwaitingMethod(offering: [.usernamePassword])
        var selection = ByteBuffer(bytes: [0x05, 0x02])
        XCTAssertEqual(try stateMachine.receiveBuffer(&selection), .sendCredentials)
        try stateMachine.sendClientCredentials()

        var partial = ByteBuffer(bytes: [0x01])
        XCTAssertEqual(try stateMachine.receiveBuffer(&partial), .waitForMoreData)
        XCTAssertEqual(partial.readableBytes, 1)
        partial.writeBytes([0x00])
        XCTAssertEqual(try stateMachine.receiveBuffer(&partial), .sendRequest)
    }

    func testClientRejectedCredentials() throws {
        var stateMachine = try self.clientStateMachineAwaitingMethod(offering: [.usernamePassword])
        var selection = ByteBuffer(bytes: [0x05, 0x02])
        XCTAssertEqual(try stateMachine.receiveBuffer(&selection), .sendCredentials)
        try stateMachine.sendClientCredentials()

        var status = ByteBuffer(bytes: [0x01, 0x01])
        XCTAssertThrowsError(try stateMachine.receiveBuffer(&status)) {
            XCTAssertEqual($0 as? SOCKSError.AuthenticationFailed, .init(status: 0x01))
        }

        // we're dead now
        var more = ByteBuffer(bytes: [0x01, 0x00])
        XCTAssertThrowsError(try stateMachine.receiveBuffer(&more)) {
            XCTAssertTrue($0 is SOCKSError.UnexpectedRead)
        }
    }

    func testClientRejectsBadSubnegotiationVersion() throws {
        var stateMachine = try self.clientStateMachineAwaitingMethod(offering: [.usernamePassword])
        var selection = ByteBuffer(bytes: [0x05, 0x02])
        XCTAssertEqual(try stateMachine.receiveBuffer(&selection), .sendCredentials)
        try stateMachine.sendClientCredentials()

        var status = ByteBuffer(bytes: [0x05, 0x00])
        XCTAssertThrowsError(try stateMachine.receiveBuffer(&status)) {
            XCTAssertEqual($0 as? SOCKSError.InvalidSubnegotiationVersion, .init(actual: 0x05))
        }
    }

    func testClientFailsInsteadOfTrappingForUnimplementedMethods() throws {
        var gssapi = try self.clientStateMachineAwaitingMethod(offering: [.noneRequired, .gssapi])
        var gssapiSelection = ByteBuffer(bytes: [0x05, 0x01])
        XCTAssertThrowsError(try gssapi.receiveBuffer(&gssapiSelection)) {
            XCTAssertEqual($0 as? SOCKSError.UnsupportedAuthenticationMethod, .init(method: .gssapi))
        }

        var custom = try self.clientStateMachineAwaitingMethod(offering: [.init(value: 0x80)])
        var customSelection = ByteBuffer(bytes: [0x05, 0x80])
        XCTAssertThrowsError(try custom.receiveBuffer(&customSelection)) {
            XCTAssertEqual($0 as? SOCKSError.UnsupportedAuthenticationMethod, .init(method: .init(value: 0x80)))
        }

        // 0xFF means "no acceptable method", whether or not it is in the list we offered
        for offered in [[AuthenticationMethod.noneRequired], [.noneRequired, .noneAcceptable]] {
            var none = try self.clientStateMachineAwaitingMethod(offering: offered)
            var noneSelection = ByteBuffer(bytes: [0x05, 0xFF])
            XCTAssertThrowsError(try none.receiveBuffer(&noneSelection)) {
                XCTAssertTrue($0 is SOCKSError.NoValidAuthenticationMethod)
            }
        }
    }

    func testClientRejectsMethodItDidNotOffer() throws {
        var stateMachine = try self.clientStateMachineAwaitingMethod(offering: [.noneRequired])
        var selection = ByteBuffer(bytes: [0x05, 0x02])
        XCTAssertThrowsError(try stateMachine.receiveBuffer(&selection)) {
            XCTAssertEqual($0 as? SOCKSError.InvalidAuthenticationSelection, .init(selection: .usernamePassword))
        }
    }

    func testServerUsernamePasswordWorkflow() throws {
        var stateMachine = ServerStateMachine()
        try stateMachine.connectionEstablished()
        var greeting = ByteBuffer(bytes: [0x05, 0x02, 0x00, 0x02])
        XCTAssertNoThrow(try stateMachine.receiveBuffer(&greeting))
        try stateMachine.sendAuthenticationMethod(.init(method: .usernamePassword))

        // dripfeed the request, it only comes out once it is complete
        let request: [UInt8] = [0x01, 0x02, 0x61, 0x62, 0x03, 0x63, 0x64, 0x65]
        var buffer = ByteBuffer()
        for byte in request.dropLast() {
            buffer.writeInteger(byte)
            XCTAssertNoThrow(XCTAssertNil(try stateMachine.receiveBuffer(&buffer)))
        }
        buffer.writeInteger(request.last!)
        // trailing bytes (the SOCKS request) must stay in the buffer
        buffer.writeBytes([0x05, 0x01])
        guard case .authenticationData(let framed)? = try stateMachine.receiveBuffer(&buffer) else {
            return XCTFail("Expected the authentication data")
        }
        XCTAssertEqual(framed, ByteBuffer(bytes: request))
        XCTAssertEqual(buffer, ByteBuffer(bytes: [0x05, 0x01]))

        try stateMachine.sendAuthenticationData(ByteBuffer(bytes: [0x01, 0x00]), complete: true)
        var connectRequest = ByteBuffer(bytes: [0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
        XCTAssertNoThrow(try stateMachine.receiveBuffer(&connectRequest))
        try stateMachine.sendServerResponse(.init(reply: .succeeded, boundAddress: .domain("127.0.0.1", port: 80)))
        XCTAssertTrue(stateMachine.proxyEstablished)
    }

    func testServerRejectsMalformedRequests() throws {
        func authenticatingServer() throws -> ServerStateMachine {
            var stateMachine = ServerStateMachine()
            try stateMachine.connectionEstablished()
            var greeting = ByteBuffer(bytes: [0x05, 0x01, 0x02])
            _ = try stateMachine.receiveBuffer(&greeting)
            try stateMachine.sendAuthenticationMethod(.init(method: .usernamePassword))
            return stateMachine
        }

        var badVersion = try authenticatingServer()
        var badVersionBytes = ByteBuffer(bytes: [0x05, 0x01, 0x61, 0x01, 0x62])
        XCTAssertThrowsError(try badVersion.receiveBuffer(&badVersionBytes)) {
            XCTAssertEqual($0 as? SOCKSError.InvalidSubnegotiationVersion, .init(actual: 0x05))
        }

        // empty fields are the server's business, not a protocol error
        var emptyUsername = try authenticatingServer()
        var emptyUsernameBytes = ByteBuffer(bytes: [0x01, 0x00, 0x01, 0x62])
        guard case .authenticationData(let framed)? = try emptyUsername.receiveBuffer(&emptyUsernameBytes) else {
            return XCTFail("Expected the authentication data")
        }
        XCTAssertEqual(framed, ByteBuffer(bytes: [0x01, 0x00, 0x01, 0x62]))
    }

    func testServerSurfacesNonUTF8RequestWithoutTrapping() throws {
        var stateMachine = ServerStateMachine()
        try stateMachine.connectionEstablished()
        var greeting = ByteBuffer(bytes: [0x05, 0x01, 0x02])
        _ = try stateMachine.receiveBuffer(&greeting)
        try stateMachine.sendAuthenticationMethod(.init(method: .usernamePassword))

        let wire: [UInt8] = [0x01, 0xFF] + [UInt8](repeating: 0xFF, count: 255) + [0x01, 0x61]
        var buffer = ByteBuffer(bytes: wire)
        guard case .authenticationData(var framed)? = try stateMachine.receiveBuffer(&buffer) else {
            return XCTFail("Expected the authentication data")
        }
        XCTAssertEqual(framed, ByteBuffer(bytes: wire))
        let request = try XCTUnwrap(try framed.readUsernamePasswordRequest())
        var again = ByteBuffer()
        again.writeUsernamePasswordRequest(request)
        XCTAssertEqual(again, ByteBuffer(bytes: wire))
    }

    func testServerCannotContinueAfterReportingFailure() throws {
        var stateMachine = ServerStateMachine()
        try stateMachine.connectionEstablished()
        var greeting = ByteBuffer(bytes: [0x05, 0x01, 0x02])
        _ = try stateMachine.receiveBuffer(&greeting)
        try stateMachine.sendAuthenticationMethod(.init(method: .usernamePassword))

        try stateMachine.sendAuthenticationData(ByteBuffer(bytes: [0x01, 0x01]), complete: true)
        XCTAssertThrowsError(try stateMachine.sendAuthenticationData(ByteBuffer(bytes: [0x01, 0x00]), complete: true)) {
            XCTAssertTrue($0 is SOCKSError.InvalidServerState)
        }
        var request = ByteBuffer(bytes: [0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 80])
        XCTAssertThrowsError(try stateMachine.receiveBuffer(&request)) {
            XCTAssertTrue($0 is SOCKSError.UnexpectedRead)
        }
    }
}

// MARK: - Handlers

private final class ErrorRecorder: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    var errors: [Error] = []

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.errors.append(error)
    }
}

/// A minimal SOCKS5 server, built from `SOCKSServerHandshakeHandler`, that checks one username / password.
private final class TestSOCKSServer: ChannelInboundHandler {
    typealias InboundIn = ClientMessage
    typealias OutboundOut = ServerMessage

    let method: AuthenticationMethod
    let expected: UsernamePasswordCredentials?
    private(set) var receivedCredentials: [UsernamePasswordCredentials] = []
    private(set) var receivedRequests: [SOCKSRequest] = []

    init(method: AuthenticationMethod, expected: UsernamePasswordCredentials?) {
        self.method = method
        self.expected = expected
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.unwrapInboundIn(data) {
        case .greeting:
            context.writeAndFlush(
                self.wrapOutboundOut(.selectedAuthenticationMethod(.init(method: self.method))),
                promise: nil
            )
        case .authenticationData(var data):
            let request = try! data.readUsernamePasswordRequest()!
            self.receivedCredentials.append(request.credentials)
            let accepted = request.credentials == self.expected
            var response = ByteBuffer()
            response.writeUsernamePasswordResponse(accepted ? .success : .failure)
            context.writeAndFlush(self.wrapOutboundOut(.authenticationData(response, complete: accepted)), promise: nil)
        case .request(let request):
            self.receivedRequests.append(request)
            context.writeAndFlush(
                self.wrapOutboundOut(.response(.init(reply: .succeeded, boundAddress: request.addressType))),
                promise: nil
            )
        }
    }
}

public class UsernamePasswordHandlerTests: XCTestCase {

    private var lastHandler: SOCKSClientHandler?
    private let address = SOCKSAddress.address(try! .init(ipAddress: "192.168.1.1", port: 80))
    private let connectRequest: [UInt8] = [0x05, 0x01, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50]
    private let connectResponse: [UInt8] = [0x05, 0x00, 0x00, 0x01, 192, 168, 1, 1, 0x00, 0x50]

    private func makeClient(
        credentials: UsernamePasswordCredentials?
    ) throws -> (EmbeddedChannel, ErrorRecorder) {
        let channel = EmbeddedChannel()
        let errors = ErrorRecorder()
        let handler = SOCKSClientHandler(targetAddress: self.address, credentials: credentials)
        self.lastHandler = handler
        try channel.pipeline.syncOperations.addHandler(handler)
        try channel.pipeline.syncOperations.addHandler(errors)
        try channel.connect(to: .init(ipAddress: "127.0.0.1", port: 1080)).wait()
        return (channel, errors)
    }

    private func readOutbound(_ channel: EmbeddedChannel) throws -> [UInt8]? {
        guard var buffer = try channel.readOutbound(as: ByteBuffer.self) else {
            return nil
        }
        return buffer.readBytes(length: buffer.readableBytes)
    }

    private func write(_ bytes: [UInt8], to channel: EmbeddedChannel) throws {
        try channel.writeInbound(ByteBuffer(bytes: bytes))
    }

    private func credentials(
        _ username: String = "alice",
        _ password: String = "hunter2"
    ) throws
        -> UsernamePasswordCredentials
    {
        try .init(username: username, password: password)
    }

    private let aliceRequest: [UInt8] =
        [0x01, 5] + Array("alice".utf8) + [7] + Array("hunter2".utf8)

    // MARK: Client against scripted bytes

    func testClientOffersUsernamePasswordOnlyWithCredentials() throws {
        let (withCredentials, _) = try self.makeClient(credentials: try self.credentials())
        XCTAssertEqual(try self.readOutbound(withCredentials), [0x05, 0x02, 0x00, 0x02])

        let (withoutCredentials, _) = try self.makeClient(credentials: nil)
        XCTAssertEqual(try self.readOutbound(withoutCredentials), [0x05, 0x01, 0x00])

        // the pre-existing initializer is unchanged
        let legacy = EmbeddedChannel(handler: SOCKSClientHandler(targetAddress: self.address))
        try legacy.connect(to: .init(ipAddress: "127.0.0.1", port: 1080)).wait()
        XCTAssertEqual(try self.readOutbound(legacy), [0x05, 0x01, 0x00])
    }

    func testClientSuccess() throws {
        let (channel, errors) = try self.makeClient(credentials: try self.credentials())
        XCTAssertEqual(try self.readOutbound(channel), [0x05, 0x02, 0x00, 0x02])

        try self.write([0x05, 0x02], to: channel)
        XCTAssertEqual(try self.readOutbound(channel), self.aliceRequest)
        XCTAssertNil(try self.readOutbound(channel))

        try self.write([0x01, 0x00], to: channel)
        XCTAssertEqual(try self.readOutbound(channel), self.connectRequest)

        try self.write(self.connectResponse, to: channel)
        XCTAssertTrue(errors.errors.isEmpty)

        // data now flows straight through
        try self.write([1, 2, 3], to: channel)
        XCTAssertEqual(try channel.readInbound(as: ByteBuffer.self), ByteBuffer(bytes: [1, 2, 3]))
        XCTAssertTrue(channel.isActive)
    }

    func testClientSkipsAuthenticationWhenServerSelectsNone() throws {
        let (channel, errors) = try self.makeClient(credentials: try self.credentials())
        XCTAssertEqual(try self.readOutbound(channel), [0x05, 0x02, 0x00, 0x02])

        try self.write([0x05, 0x00], to: channel)
        // no credentials are sent to a server that doesn't ask for them
        XCTAssertEqual(try self.readOutbound(channel), self.connectRequest)
        try self.write(self.connectResponse, to: channel)
        XCTAssertTrue(errors.errors.isEmpty)
    }

    func testClientWrongPassword() throws {
        let (channel, errors) = try self.makeClient(credentials: try self.credentials())
        _ = try self.readOutbound(channel)
        try self.write([0x05, 0x02], to: channel)
        XCTAssertEqual(try self.readOutbound(channel), self.aliceRequest)

        try self.write([0x01, 0x01], to: channel)
        XCTAssertEqual(errors.errors.count, 1)
        XCTAssertEqual(errors.errors.first as? SOCKSError.AuthenticationFailed, .init(status: 0x01))
        XCTAssertFalse(channel.isActive)
        // the connect request must never be sent after a failed authentication
        XCTAssertNil(try self.readOutbound(channel))
    }

    func testClientServerSelectsMethodNotOffered() throws {
        // no credentials: usernamePassword was never offered
        let (channel, errors) = try self.makeClient(credentials: nil)
        _ = try self.readOutbound(channel)
        try self.write([0x05, 0x02], to: channel)
        XCTAssertEqual(
            errors.errors.first as? SOCKSError.InvalidAuthenticationSelection,
            .init(selection: .usernamePassword)
        )
        XCTAssertFalse(channel.isActive)
        XCTAssertNil(try self.readOutbound(channel))

        // with credentials: GSSAPI was never offered
        let (other, otherErrors) = try self.makeClient(credentials: try self.credentials())
        _ = try self.readOutbound(other)
        try self.write([0x05, 0x01], to: other)
        XCTAssertEqual(
            otherErrors.errors.first as? SOCKSError.InvalidAuthenticationSelection,
            .init(selection: .gssapi)
        )
        XCTAssertFalse(other.isActive)
    }

    func testClientServerSelectsNoneAcceptable() throws {
        for credentials in [nil, try self.credentials()] {
            let (channel, errors) = try self.makeClient(credentials: credentials)
            _ = try self.readOutbound(channel)
            try self.write([0x05, 0xFF], to: channel)
            XCTAssertEqual(errors.errors.count, 1)
            XCTAssertTrue(errors.errors.first is SOCKSError.NoValidAuthenticationMethod)
            XCTAssertFalse(channel.isActive)
            XCTAssertNil(try self.readOutbound(channel))
        }
    }

    func testClientFragmentedReads() throws {
        let (channel, errors) = try self.makeClient(credentials: try self.credentials())
        _ = try self.readOutbound(channel)

        // method selection, one byte at a time
        try self.write([0x05], to: channel)
        XCTAssertNil(try self.readOutbound(channel))
        try self.write([0x02], to: channel)
        XCTAssertEqual(try self.readOutbound(channel), self.aliceRequest)

        // status, one byte at a time
        try self.write([0x01], to: channel)
        XCTAssertNil(try self.readOutbound(channel))
        try self.write([0x00], to: channel)
        XCTAssertEqual(try self.readOutbound(channel), self.connectRequest)

        // whole thing glued together with the first bytes of the tunnel
        try self.write(self.connectResponse + [9, 9], to: channel)
        XCTAssertEqual(try channel.readInbound(as: ByteBuffer.self), ByteBuffer(bytes: [9, 9]))
        XCTAssertTrue(errors.errors.isEmpty)
    }

    func testClientBadSubnegotiationVersion() throws {
        let (channel, errors) = try self.makeClient(credentials: try self.credentials())
        _ = try self.readOutbound(channel)
        try self.write([0x05, 0x02], to: channel)
        _ = try self.readOutbound(channel)
        try self.write([0x05, 0x00], to: channel)
        XCTAssertEqual(errors.errors.first as? SOCKSError.InvalidSubnegotiationVersion, .init(actual: 0x05))
        XCTAssertFalse(channel.isActive)
    }

    func testClientCredentialsAtTheLimit() throws {
        let username = String(repeating: "u", count: 255)
        let password = String(repeating: "p", count: 255)
        let (channel, errors) = try self.makeClient(credentials: try self.credentials(username, password))
        _ = try self.readOutbound(channel)
        try self.write([0x05, 0x02], to: channel)

        let expected = [0x01, 255] + Array(username.utf8) + [255] + Array(password.utf8)
        XCTAssertEqual(try self.readOutbound(channel), expected)
        XCTAssertEqual(expected.count, 513)
        try self.write([0x01, 0x00], to: channel)
        XCTAssertEqual(try self.readOutbound(channel), self.connectRequest)
        XCTAssertTrue(errors.errors.isEmpty)
    }

    func testCredentialsOneByteOverTheLimitCannotBeCreated() {
        XCTAssertThrowsError(
            try UsernamePasswordCredentials(username: String(repeating: "u", count: 256), password: "p")
        ) {
            XCTAssertEqual($0 as? SOCKSError.InvalidCredentialLength, .init(field: .username, actual: 256))
        }
        XCTAssertThrowsError(
            try UsernamePasswordCredentials(username: "u", password: String(repeating: "p", count: 256))
        ) {
            XCTAssertEqual($0 as? SOCKSError.InvalidCredentialLength, .init(field: .password, actual: 256))
        }
    }

    // MARK: Client <-> server

    /// Moves everything written by one side to the other until both are quiet.
    private func pump(_ client: EmbeddedChannel, _ server: EmbeddedChannel) throws {
        var moved = true
        while moved {
            moved = false
            while let buffer = try client.readOutbound(as: ByteBuffer.self) {
                try server.writeInbound(buffer)
                moved = true
            }
            while let buffer = try server.readOutbound(as: ByteBuffer.self) {
                try client.writeInbound(buffer)
                moved = true
            }
        }
    }

    private func makeServer(
        method: AuthenticationMethod,
        expected: UsernamePasswordCredentials?
    ) throws -> (EmbeddedChannel, TestSOCKSServer) {
        let server = EmbeddedChannel()
        let logic = TestSOCKSServer(method: method, expected: expected)
        try server.pipeline.syncOperations.addHandler(SOCKSServerHandshakeHandler())
        try server.pipeline.syncOperations.addHandler(logic)
        try server.connect(to: .init(ipAddress: "127.0.0.1", port: 1234)).wait()
        return (server, logic)
    }

    func testEndToEndSuccess() throws {
        let (server, logic) = try self.makeServer(method: .usernamePassword, expected: try self.credentials())
        let (client, errors) = try self.makeClient(credentials: try self.credentials())
        try self.pump(client, server)

        XCTAssertTrue(errors.errors.isEmpty)
        XCTAssertEqual(logic.receivedCredentials, [try self.credentials()])
        XCTAssertEqual(logic.receivedRequests.count, 1)

        // tunnel is up in both directions
        client.writeAndFlush(ByteBuffer(bytes: [1, 2, 3]), promise: nil)
        XCTAssertEqual(try self.readOutbound(client), [1, 2, 3])
    }

    func testEndToEndWrongPassword() throws {
        let (server, logic) = try self.makeServer(method: .usernamePassword, expected: try self.credentials())
        let (client, errors) = try self.makeClient(credentials: try self.credentials("alice", "wrong"))
        try self.pump(client, server)

        XCTAssertEqual(errors.errors.first as? SOCKSError.AuthenticationFailed, .init(status: 0x01))
        XCTAssertFalse(client.isActive)
        XCTAssertEqual(logic.receivedCredentials, [try self.credentials("alice", "wrong")])
        XCTAssertTrue(logic.receivedRequests.isEmpty)
    }

    func testEndToEndCredentialsAtTheLimit() throws {
        let credentials = try self.credentials(String(repeating: "u", count: 255), String(repeating: "p", count: 255))
        let (server, logic) = try self.makeServer(method: .usernamePassword, expected: credentials)
        let (client, errors) = try self.makeClient(credentials: credentials)
        try self.pump(client, server)

        XCTAssertTrue(errors.errors.isEmpty)
        XCTAssertEqual(logic.receivedCredentials, [credentials])
        XCTAssertEqual(logic.receivedRequests.count, 1)
    }

    func testEndToEndServerNeedsNoAuthentication() throws {
        let (server, logic) = try self.makeServer(method: .noneRequired, expected: nil)
        let (client, errors) = try self.makeClient(credentials: try self.credentials())
        try self.pump(client, server)

        XCTAssertTrue(errors.errors.isEmpty)
        XCTAssertTrue(logic.receivedCredentials.isEmpty)
        XCTAssertEqual(logic.receivedRequests.count, 1)
    }

    func testEndToEndFragmentedByteByByte() throws {
        let (server, logic) = try self.makeServer(method: .usernamePassword, expected: try self.credentials())
        let (client, errors) = try self.makeClient(credentials: try self.credentials())

        var moved = true
        while moved {
            moved = false
            while var buffer = try client.readOutbound(as: ByteBuffer.self) {
                for byte in buffer.readBytes(length: buffer.readableBytes)! {
                    try server.writeInbound(ByteBuffer(bytes: [byte]))
                }
                moved = true
            }
            while var buffer = try server.readOutbound(as: ByteBuffer.self) {
                for byte in buffer.readBytes(length: buffer.readableBytes)! {
                    try client.writeInbound(ByteBuffer(bytes: [byte]))
                }
                moved = true
            }
        }

        XCTAssertTrue(errors.errors.isEmpty)
        XCTAssertEqual(logic.receivedCredentials, [try self.credentials()])
        XCTAssertEqual(logic.receivedRequests.count, 1)
    }

    // MARK: More client behavior

    func testClientEmptyPasswordWire() throws {
        let (channel, errors) = try self.makeClient(credentials: try self.credentials("alice", ""))
        _ = try self.readOutbound(channel)
        try self.write([0x05, 0x02], to: channel)
        XCTAssertEqual(try self.readOutbound(channel), [0x01, 5] + Array("alice".utf8) + [0])
        try self.write([0x01, 0x00], to: channel)
        XCTAssertEqual(try self.readOutbound(channel), self.connectRequest)
        XCTAssertTrue(errors.errors.isEmpty)
    }

    func testClientNonASCIICredentialsAreSentAsUTF8() throws {
        let (channel, errors) = try self.makeClient(credentials: try self.credentials("\u{e9}", "\u{f1}"))
        _ = try self.readOutbound(channel)
        try self.write([0x05, 0x02], to: channel)
        XCTAssertEqual(try self.readOutbound(channel), [0x01, 0x02, 0xC3, 0xA9, 0x02, 0xC3, 0xB1])
        try self.write([0x01, 0x00], to: channel)
        XCTAssertEqual(try self.readOutbound(channel), self.connectRequest)
        XCTAssertTrue(errors.errors.isEmpty)
    }

    func testClientAnyNonZeroStatusIsAFailure() throws {
        for status: UInt8 in [0x01, 0x7F, 0xFF] {
            let (channel, errors) = try self.makeClient(credentials: try self.credentials())
            _ = try self.readOutbound(channel)
            try self.write([0x05, 0x02], to: channel)
            _ = try self.readOutbound(channel)
            try self.write([0x01, status], to: channel)
            XCTAssertEqual(errors.errors.first as? SOCKSError.AuthenticationFailed, .init(status: status))
            XCTAssertFalse(channel.isActive)
            XCTAssertNil(try self.readOutbound(channel))
        }
    }

    func testHandlerRemovalRequestedDuringAuthenticationSucceeds() throws {
        let (channel, errors) = try self.makeClient(credentials: try self.credentials())
        let handler = try XCTUnwrap(self.lastHandler)
        _ = try self.readOutbound(channel)
        try self.write([0x05, 0x02], to: channel)
        XCTAssertEqual(try self.readOutbound(channel), self.aliceRequest)

        // removal is requested while we wait for the status, the handler has to stay until the proxy is up
        let removal = channel.eventLoop.makePromise(of: Void.self)
        channel.pipeline.syncOperations.removeHandler(handler, promise: removal)
        XCTAssertNoThrow(try channel.pipeline.syncOperations.handler(type: SOCKSClientHandler.self))

        try self.write([0x01, 0x00], to: channel)
        XCTAssertEqual(try self.readOutbound(channel), self.connectRequest)
        XCTAssertNoThrow(try channel.pipeline.syncOperations.handler(type: SOCKSClientHandler.self))

        try self.write(self.connectResponse + [9], to: channel)
        XCTAssertNoThrow(try removal.futureResult.wait())
        XCTAssertThrowsError(try channel.pipeline.syncOperations.handler(type: SOCKSClientHandler.self))
        XCTAssertEqual(try channel.readInbound(as: ByteBuffer.self), ByteBuffer(bytes: [9]))
        XCTAssertTrue(errors.errors.isEmpty)
        XCTAssertTrue(channel.isActive)
    }

    func testHandlerRemovalRequestedDuringAuthenticationFails() throws {
        let (channel, errors) = try self.makeClient(credentials: try self.credentials())
        let handler = try XCTUnwrap(self.lastHandler)
        _ = try self.readOutbound(channel)
        try self.write([0x05, 0x02], to: channel)
        _ = try self.readOutbound(channel)

        let removal = channel.eventLoop.makePromise(of: Void.self)
        channel.pipeline.syncOperations.removeHandler(handler, promise: removal)

        try self.write([0x01, 0x01], to: channel)
        XCTAssertEqual(errors.errors.first as? SOCKSError.AuthenticationFailed, .init(status: 0x01))
        XCTAssertFalse(channel.isActive)
        XCTAssertNil(try self.readOutbound(channel))
        // Note: like after a failed connect request, the handler only completes a pending removal once
        // the proxy is established, so `removal` is intentionally not awaited here.
    }

    func testWritesDuringAuthenticationAreFlushedInOrderAfterEstablishment() throws {
        let (channel, _) = try self.makeClient(credentials: try self.credentials())
        let first = channel.eventLoop.makePromise(of: Void.self)
        let second = channel.eventLoop.makePromise(of: Void.self)
        channel.write(ByteBuffer(bytes: [1, 2, 3]), promise: first)
        channel.flush()
        channel.write(ByteBuffer(bytes: [4, 5, 6]), promise: second)

        XCTAssertEqual(try self.readOutbound(channel), [0x05, 0x02, 0x00, 0x02])
        try self.write([0x05, 0x02], to: channel)
        // only the credentials, never application data, before the tunnel exists
        XCTAssertEqual(try self.readOutbound(channel), self.aliceRequest)
        XCTAssertNil(try self.readOutbound(channel))
        try self.write([0x01, 0x00], to: channel)
        XCTAssertEqual(try self.readOutbound(channel), self.connectRequest)
        XCTAssertNil(try self.readOutbound(channel))

        try self.write(self.connectResponse, to: channel)
        XCTAssertNoThrow(try first.futureResult.wait())
        XCTAssertEqual(try self.readOutbound(channel), [1, 2, 3])
        // the second write was not flushed yet
        XCTAssertNil(try self.readOutbound(channel))
        channel.flush()
        XCTAssertNoThrow(try second.futureResult.wait())
        XCTAssertEqual(try self.readOutbound(channel), [4, 5, 6])
    }

    func testWritesFailedAuthenticationNeverReachTheNetwork() throws {
        let (channel, _) = try self.makeClient(credentials: try self.credentials())
        channel.writeAndFlush(ByteBuffer(bytes: [1, 2, 3]), promise: nil)
        _ = try self.readOutbound(channel)
        try self.write([0x05, 0x02], to: channel)
        _ = try self.readOutbound(channel)
        try self.write([0x01, 0x01], to: channel)
        XCTAssertNil(try self.readOutbound(channel))
    }

    func testDumpOfTheHandlerDoesNotLeakThePassword() throws {
        let handler = SOCKSClientHandler(
            targetAddress: self.address,
            credentials: try self.credentials("alice", "hunter2")
        )
        var text = ""
        dump(handler, to: &text)
        XCTAssertTrue(text.contains("alice"), text)
        XCTAssertFalse(text.contains("hunter2"), text)
        XCTAssertFalse(text.contains("104"), text)
        XCTAssertTrue(text.contains("<redacted>"), text)

        // also once the handshake is running
        let (channel, _) = try self.makeClient(credentials: try self.credentials("alice", "hunter2"))
        _ = try self.readOutbound(channel)
        try self.write([0x05, 0x02], to: channel)
        var running = ""
        dump(try XCTUnwrap(self.lastHandler), to: &running)
        XCTAssertFalse(running.contains("hunter2"), running)
    }

    // MARK: More client <-> server

    func testEndToEndEmptyPassword() throws {
        let credentials = try self.credentials("alice", "")
        let (server, logic) = try self.makeServer(method: .usernamePassword, expected: credentials)
        let (client, errors) = try self.makeClient(credentials: credentials)
        try self.pump(client, server)

        XCTAssertTrue(errors.errors.isEmpty)
        XCTAssertEqual(logic.receivedCredentials, [credentials])
        XCTAssertEqual(logic.receivedRequests.count, 1)
    }

    func testEndToEndNonASCII() throws {
        let credentials = try self.credentials("\u{e9}", "\u{f1}\u{1F600}")
        let (server, logic) = try self.makeServer(method: .usernamePassword, expected: credentials)
        let (client, errors) = try self.makeClient(credentials: credentials)
        try self.pump(client, server)

        XCTAssertTrue(errors.errors.isEmpty)
        XCTAssertEqual(logic.receivedCredentials, [credentials])
        XCTAssertEqual(logic.receivedRequests.count, 1)
    }

    func testServerHandlerAcceptsEmptyUsernameAndPasswordOnTheWire() throws {
        for (wire, username, password) in [
            ([UInt8]([0x01, 0x00, 0x01, 0x62]), [UInt8](), [UInt8]([0x62])),
            ([0x01, 0x01, 0x61, 0x00], [0x61], []),
            ([0x01, 0x00, 0x00], [], []),
        ] {
            let (server, logic) = try self.makeServer(method: .usernamePassword, expected: try self.credentials())
            try self.write([0x05, 0x01, 0x02], to: server)
            XCTAssertEqual(try self.readOutbound(server), [0x05, 0x02])

            // a server can reject them with a failure status, not by dropping the connection
            try self.write(wire, to: server)
            XCTAssertEqual(logic.receivedCredentials.count, 1)
            XCTAssertEqual(logic.receivedCredentials.first?.usernameBytes, username)
            XCTAssertEqual(logic.receivedCredentials.first?.passwordBytes, password)
            XCTAssertEqual(try self.readOutbound(server), [0x01, 0x01])
            XCTAssertTrue(server.isActive)
        }
    }

    func testServerHandlerWithHostileNonUTF8Credentials() throws {
        let (server, logic) = try self.makeServer(method: .usernamePassword, expected: try self.credentials())
        try self.write([0x05, 0x01, 0x02], to: server)
        _ = try self.readOutbound(server)

        let wire: [UInt8] = [0x01, 0xFF] + [UInt8](repeating: 0xFF, count: 255) + [0x01, 0x61]
        try self.write(wire, to: server)
        XCTAssertEqual(logic.receivedCredentials.count, 1)
        XCTAssertEqual(logic.receivedCredentials.first?.usernameBytes, [UInt8](repeating: 0xFF, count: 255))
        XCTAssertEqual(try self.readOutbound(server), [0x01, 0x01])

        // and the same bytes with another byte value are different credentials
        let (other, otherLogic) = try self.makeServer(method: .usernamePassword, expected: try self.credentials())
        try self.write([0x05, 0x01, 0x02], to: other)
        _ = try self.readOutbound(other)
        try self.write([0x01, 0xFF] + [UInt8](repeating: 0xFE, count: 255) + [0x01, 0x61], to: other)
        XCTAssertNotEqual(otherLogic.receivedCredentials, logic.receivedCredentials)
    }
}
