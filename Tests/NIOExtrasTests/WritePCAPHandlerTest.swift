//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019-2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CNIOLinux
import Foundation
import NIOCore
import NIOEmbedded
import XCTest

@testable import NIOExtras

#if canImport(Android)
import Android
#endif

class WritePCAPHandlerTest: XCTestCase {
    private var accumulatedPackets: [ByteBuffer]!
    private var channel: EmbeddedChannel!
    private var scratchBuffer: ByteBuffer!
    private var testAddressA: SocketAddress.IPv6Address!

    private var _mode: NIOWritePCAPHandler.Mode = .client
    var mode: NIOWritePCAPHandler.Mode {
        get {
            self._mode
        }
        set {
            self.channel = EmbeddedChannel(
                handler: NIOWritePCAPHandler(
                    mode: newValue,
                    fakeLocalAddress: nil,
                    fakeRemoteAddress: nil,
                    fileSink: {
                        self.accumulatedPackets.append($0)
                    }
                )
            )
            self._mode = newValue
        }
    }

    override func setUp() {
        self.accumulatedPackets = []
        self.channel = EmbeddedChannel()
        XCTAssertNoThrow(
            try self.channel.pipeline.syncOperations.addHandler(
                NIOWritePCAPHandler(
                    mode: .client,
                    fakeLocalAddress: nil,
                    fakeRemoteAddress: nil,
                    fileSink: {
                        self.accumulatedPackets.append($0)
                    }
                ),
                name: "NIOWritePCAPHandler"
            )
        )
        self.scratchBuffer = self.channel.allocator.buffer(capacity: 128)
    }

    override func tearDown() {
        self.accumulatedPackets = nil
        self.channel = nil
        self.scratchBuffer = nil
    }

    func assertEqual(
        expectedAddress: SocketAddress?,
        actualIPv4Address: in_addr,
        actualPort: UInt16,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let port = expectedAddress?.port else {
            XCTFail("expected address nil or has no port", file: (file), line: line)
            return
        }
        switch expectedAddress {
        case .some(.v4(let expectedAddress)):
            XCTAssertEqual(
                expectedAddress.address.sin_addr.s_addr,
                actualIPv4Address.s_addr,
                "IP addresses don't match",
                file: (file),
                line: line
            )
            XCTAssertEqual(port, Int(actualPort), "ports don't match", file: (file), line: line)
        default:
            XCTFail("expected address not an IPv4 address", file: (file), line: line)
        }
    }

    func assertEqual(
        expectedAddress: SocketAddress?,
        actualIPv6Address: in6_addr,
        actualPort: UInt16,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let port = expectedAddress?.port else {
            XCTFail("expected address nil or has no port", file: (file), line: line)
            return
        }
        switch expectedAddress {
        case .some(.v6(let expectedAddress)):
            var actualIPv6Address = actualIPv6Address
            var expectedAddress = expectedAddress.address
            withUnsafeBytes(of: &actualIPv6Address) { actualAddressBytes in
                withUnsafeBytes(of: &expectedAddress.sin6_addr) { expectedAddressBytes in
                    XCTAssertEqual(actualAddressBytes.count, expectedAddressBytes.count)
                }
            }
            XCTAssertEqual(port, Int(actualPort), "ports don't match", file: (file), line: line)
        default:
            XCTFail("expected address not an IPv4 address", file: (file), line: line)
        }
    }

    func testConnectIssuesThreePacketsForIPv4() throws {
        XCTAssertEqual([], self.accumulatedPackets)
        self.channel.localAddress = try! SocketAddress(ipAddress: "255.255.255.254", port: Int(UInt16.max) - 1)
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5678)).wait())
        XCTAssertNoThrow(try self.channel.throwIfErrorCaught())
        XCTAssertEqual(1, self.accumulatedPackets.count)  // the WritePCAPHandler will batch all into one write
        var buffer = self.accumulatedPackets.first
        let records = [
            buffer?.readPCAPRecord(),  // SYN
            buffer?.readPCAPRecord(),  // SYN+ACK
            buffer?.readPCAPRecord(),  // ACK
        ]
        var ipPackets: [TCPIPv4Packet] = []
        for var record in records {
            XCTAssertNotNil(record)  // we must have been able to parse a record
            XCTAssertGreaterThan(record?.payload.readableBytes ?? -1, 0)  // there must be some TCP/IP packet in there
            XCTAssertEqual(2, record?.pcapProtocolID)  // 2 is IPv4
            if let ipPacket = try record?.payload.readTCPIPv4() {
                ipPackets.append(ipPacket)
                XCTAssertEqual(0, ipPacket.tcpPayload.readableBytes)
                XCTAssertEqual(40, ipPacket.wholeIPPacketLength)  // in IPv4 it's payload + IP + TCP header
            }
        }
        XCTAssertEqual(3, ipPackets.count)

        // SYN, local should be source, remote is destination
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv4Address: ipPackets[0].src,
            actualPort: ipPackets[0].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv4Address: ipPackets[0].dst,
            actualPort: ipPackets[0].tcpHeader.dstPort
        )
        XCTAssertEqual([.syn], ipPackets[0].tcpHeader.flags)

        // SYN+ACK, local should be destination, remote should be source
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv4Address: ipPackets[1].src,
            actualPort: ipPackets[1].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv4Address: ipPackets[1].dst,
            actualPort: ipPackets[1].tcpHeader.dstPort
        )
        XCTAssertEqual([.syn, .ack], ipPackets[1].tcpHeader.flags)

        // ACK
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv4Address: ipPackets[0].src,
            actualPort: ipPackets[0].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv4Address: ipPackets[0].dst,
            actualPort: ipPackets[0].tcpHeader.dstPort
        )
        XCTAssertEqual([.ack], ipPackets[2].tcpHeader.flags)

        XCTAssertEqual(0, buffer?.readableBytes)  // there shouldn't be anything else left
    }

    func testConnectIssuesThreePacketsForIPv6() throws {
        XCTAssertEqual([], self.accumulatedPackets)
        self.channel.localAddress = try! SocketAddress(ipAddress: "1:2:3:4:5:6:7:8", port: Int(UInt16.max) - 1)
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "::1", port: 5678)).wait())
        XCTAssertNoThrow(try self.channel.throwIfErrorCaught())
        XCTAssertEqual(1, self.accumulatedPackets.count)  // the WritePCAPHandler will batch all into one write
        var buffer = self.accumulatedPackets.first
        let records = [
            buffer?.readPCAPRecord(),  // SYN
            buffer?.readPCAPRecord(),  // SYN+ACK
            buffer?.readPCAPRecord(),  // ACK
        ]
        var ipPackets: [TCPIPv6Packet] = []
        for var record in records {
            XCTAssertNotNil(record)  // we must have been able to parse a record
            XCTAssertGreaterThan(record?.payload.readableBytes ?? -1, 0)  // there must be some TCP/IP packet in there
            XCTAssertEqual(24, record?.pcapProtocolID)  // 24 is IPv6
            if let ipPacket = try record?.payload.readTCPIPv6() {
                ipPackets.append(ipPacket)
                XCTAssertEqual(0, ipPacket.tcpPayload.readableBytes)
                XCTAssertEqual(20, ipPacket.payloadLength)  // in IPv6 it's just the payload, ie. payload + TCP header
            }
        }
        XCTAssertEqual(3, ipPackets.count)

        // SYN, local should be source, remote is destination
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv6Address: ipPackets[0].src,
            actualPort: ipPackets[0].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv6Address: ipPackets[0].dst,
            actualPort: ipPackets[0].tcpHeader.dstPort
        )
        XCTAssertEqual([.syn], ipPackets[0].tcpHeader.flags)

        // SYN+ACK, local should be destination, remote should be source
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv6Address: ipPackets[1].src,
            actualPort: ipPackets[1].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv6Address: ipPackets[1].dst,
            actualPort: ipPackets[1].tcpHeader.dstPort
        )
        XCTAssertEqual([.syn, .ack], ipPackets[1].tcpHeader.flags)

        // ACK
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv6Address: ipPackets[0].src,
            actualPort: ipPackets[0].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv6Address: ipPackets[0].dst,
            actualPort: ipPackets[0].tcpHeader.dstPort
        )
        XCTAssertEqual([.ack], ipPackets[2].tcpHeader.flags)

        XCTAssertEqual(0, buffer?.readableBytes)  // there shouldn't be anything else left
    }

    func testAcceptConnectionFromRemote() throws {
        self.mode = .server

        XCTAssertEqual([], self.accumulatedPackets)
        self.channel.remoteAddress = try! SocketAddress(ipAddress: "1.2.3.4", port: 5678)
        self.channel.localAddress = try! SocketAddress(ipAddress: "255.255.255.254", port: Int(UInt16.max) - 1)
        channel.pipeline.fireChannelActive()
        XCTAssertNoThrow(try self.channel.throwIfErrorCaught())
        XCTAssertEqual(1, self.accumulatedPackets.count)  // the WritePCAPHandler will batch all into one write
        var buffer = self.accumulatedPackets.first
        let records = [
            buffer?.readPCAPRecord(),  // SYN
            buffer?.readPCAPRecord(),  // SYN+ACK
            buffer?.readPCAPRecord(),  // ACK
        ]
        var ipPackets: [TCPIPv4Packet] = []
        for var record in records {
            XCTAssertNotNil(record)  // we must have been able to parse a record
            XCTAssertGreaterThan(record?.payload.readableBytes ?? -1, 0)  // there must be some TCP/IP packet in there
            XCTAssertEqual(2, record?.pcapProtocolID)  // 2 is IPv4
            if let ipPacket = try record?.payload.readTCPIPv4() {
                ipPackets.append(ipPacket)
                XCTAssertEqual(0, ipPacket.tcpPayload.readableBytes)
            }
        }
        XCTAssertEqual(3, ipPackets.count)

        // SYN, local should be dst, remote is src
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv4Address: ipPackets[0].src,
            actualPort: ipPackets[0].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv4Address: ipPackets[0].dst,
            actualPort: ipPackets[0].tcpHeader.dstPort
        )
        XCTAssertEqual([.syn], ipPackets[0].tcpHeader.flags)

        // SYN+ACK, local should be src, remote should be dst
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv4Address: ipPackets[1].src,
            actualPort: ipPackets[1].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv4Address: ipPackets[1].dst,
            actualPort: ipPackets[1].tcpHeader.dstPort
        )
        XCTAssertEqual([.syn, .ack], ipPackets[1].tcpHeader.flags)

        // ACK
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv4Address: ipPackets[0].src,
            actualPort: ipPackets[0].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv4Address: ipPackets[0].dst,
            actualPort: ipPackets[0].tcpHeader.dstPort
        )
        XCTAssertEqual([.ack], ipPackets[2].tcpHeader.flags)

        XCTAssertEqual(0, buffer?.readableBytes)  // there shouldn't be anything else left
    }

    func testCloseOriginatingFromLocal() throws {
        self.channel.localAddress = try! SocketAddress(ipAddress: "1.1.1.1", port: 1)
        self.channel.remoteAddress = try! SocketAddress(ipAddress: "2.2.2.2", port: 2)
        XCTAssertNoThrow(try self.channel.close().wait())

        XCTAssertEqual(1, self.accumulatedPackets.count)  // we're batching again.

        var buffer = self.accumulatedPackets.first
        let records = [
            buffer?.readPCAPRecord(),  // FIN
            buffer?.readPCAPRecord(),  // FIN+ACK
            buffer?.readPCAPRecord(),  // ACK
        ]
        XCTAssertEqual(0, buffer?.readableBytes)  // nothing left
        var ipPackets: [TCPIPv4Packet] = []
        for var record in records {
            XCTAssertNotNil(record)  // we must have been able to parse a record
            XCTAssertGreaterThan(record?.payload.readableBytes ?? -1, 0)  // there must be some TCP/IP packet in there
            if let ipPacket = try record?.payload.readTCPIPv4() {
                ipPackets.append(ipPacket)
                XCTAssertEqual(0, ipPacket.tcpPayload.readableBytes)
            }
        }

        // FIN, local should be source, remote is destination
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv4Address: ipPackets[0].src,
            actualPort: ipPackets[0].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv4Address: ipPackets[0].dst,
            actualPort: ipPackets[0].tcpHeader.dstPort
        )
        XCTAssertEqual([.fin], ipPackets[0].tcpHeader.flags)

        // FIN+ACK, local should be destination, remote should be source
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv4Address: ipPackets[1].src,
            actualPort: ipPackets[1].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv4Address: ipPackets[1].dst,
            actualPort: ipPackets[1].tcpHeader.dstPort
        )
        XCTAssertEqual([.fin, .ack], ipPackets[1].tcpHeader.flags)

        // ACK
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv4Address: ipPackets[0].src,
            actualPort: ipPackets[0].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv4Address: ipPackets[0].dst,
            actualPort: ipPackets[0].tcpHeader.dstPort
        )
        XCTAssertEqual([.ack], ipPackets[2].tcpHeader.flags)
    }

    func testCloseOriginatingFromRemote() throws {
        self.channel.localAddress = try! SocketAddress(ipAddress: "1.1.1.1", port: 1)
        self.channel.remoteAddress = try! SocketAddress(ipAddress: "2.2.2.2", port: 2)
        self.channel.pipeline.fireChannelInactive()

        XCTAssertEqual(1, self.accumulatedPackets.count)  // we're batching again.

        var buffer = self.accumulatedPackets.first
        let records = [
            buffer?.readPCAPRecord(),  // FIN
            buffer?.readPCAPRecord(),  // FIN+ACK
            buffer?.readPCAPRecord(),  // ACK
        ]
        XCTAssertEqual(0, buffer?.readableBytes)  // nothing left
        var ipPackets: [TCPIPv4Packet] = []
        for var record in records {
            XCTAssertNotNil(record)  // we must have been able to parse a record
            XCTAssertGreaterThan(record?.payload.readableBytes ?? -1, 0)  // there must be some TCP/IP packet in there
            if let ipPacket = try record?.payload.readTCPIPv4() {
                ipPackets.append(ipPacket)
                XCTAssertEqual(0, ipPacket.tcpPayload.readableBytes)
            }
        }

        // FIN, local should be dst, remote is src
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv4Address: ipPackets[0].src,
            actualPort: ipPackets[0].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv4Address: ipPackets[0].dst,
            actualPort: ipPackets[0].tcpHeader.dstPort
        )
        XCTAssertEqual([.fin], ipPackets[0].tcpHeader.flags)

        // FIN+ACK, local should be src, remote should be dst
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv4Address: ipPackets[1].src,
            actualPort: ipPackets[1].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv4Address: ipPackets[1].dst,
            actualPort: ipPackets[1].tcpHeader.dstPort
        )
        XCTAssertEqual([.fin, .ack], ipPackets[1].tcpHeader.flags)

        // ACK
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv4Address: ipPackets[0].src,
            actualPort: ipPackets[0].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv4Address: ipPackets[0].dst,
            actualPort: ipPackets[0].tcpHeader.dstPort
        )
        XCTAssertEqual([.ack], ipPackets[2].tcpHeader.flags)
    }

    func testInboundData() throws {
        self.channel.localAddress = try! SocketAddress(ipAddress: "1.2.3.4", port: 1111)
        self.channel.remoteAddress = try! SocketAddress(ipAddress: "9.8.7.6", port: 2222)
        self.scratchBuffer.writeStaticString("hello")
        XCTAssertNoThrow(try self.channel.writeInbound(self.scratchBuffer))
        XCTAssertEqual(1, self.accumulatedPackets.count)

        guard var packetBytes = self.accumulatedPackets.first else {
            XCTFail("couldn't read bytes of first packet")
            return
        }
        guard var payload = packetBytes.readPCAPRecord() else {
            XCTFail("couldn't read payload from PCAP record")
            return
        }
        XCTAssertEqual(0, packetBytes.readableBytes)  // check nothing is left over
        guard let tcpIPPacket = try payload.payload.readTCPIPv4() else {
            XCTFail("couldn't read TCP/IPv4 packet")
            return
        }
        XCTAssertEqual(1111, tcpIPPacket.tcpHeader.dstPort)
        XCTAssertEqual(2222, tcpIPPacket.tcpHeader.srcPort)
        XCTAssertEqual("hello", String(decoding: tcpIPPacket.tcpPayload.readableBytesView, as: Unicode.UTF8.self))
    }

    func testOutboundData() throws {
        self.channel.localAddress = try! SocketAddress(ipAddress: "1.2.3.4", port: 1111)
        self.channel.remoteAddress = try! SocketAddress(ipAddress: "9.8.7.6", port: 2222)
        self.scratchBuffer.writeStaticString("hello")
        XCTAssertNoThrow(try self.channel.writeOutbound(self.scratchBuffer))
        XCTAssertEqual(1, self.accumulatedPackets.count)

        guard var packetBytes = self.accumulatedPackets.first else {
            XCTFail("couldn't read bytes of first packet")
            return
        }
        guard var payload = packetBytes.readPCAPRecord() else {
            XCTFail("couldn't read payload from PCAP record")
            return
        }
        XCTAssertEqual(0, packetBytes.readableBytes)  // check nothing is left over
        guard let tcpIPPacket = try payload.payload.readTCPIPv4() else {
            XCTFail("couldn't read TCP/IPv4 packet")
            return
        }
        XCTAssertEqual(2222, tcpIPPacket.tcpHeader.dstPort)
        XCTAssertEqual(1111, tcpIPPacket.tcpHeader.srcPort)
        XCTAssertEqual("hello", String(decoding: tcpIPPacket.tcpPayload.readableBytesView, as: Unicode.UTF8.self))
    }

    func testOversizedInboundDataComesAsTwoPacketsIPv4() throws {
        self.channel.localAddress = try! SocketAddress(ipAddress: "1.2.3.4", port: 1111)
        self.channel.remoteAddress = try! SocketAddress(ipAddress: "9.8.7.6", port: 2222)
        let expectedData = String(repeating: "X", count: Int(UInt16.max) * 2 - 300)
        self.scratchBuffer.writeString(expectedData)
        XCTAssertNoThrow(try self.channel.writeInbound(self.scratchBuffer))
        XCTAssertEqual(1, self.accumulatedPackets.count)

        guard var packetBytes = self.accumulatedPackets.first else {
            XCTFail("couldn't read bytes of first packet")
            return
        }
        guard var payload1 = packetBytes.readPCAPRecord(), var payload2 = packetBytes.readPCAPRecord() else {
            XCTFail("couldn't read payloads from PCAP record")
            return
        }
        XCTAssertEqual(0, packetBytes.readableBytes)  // check nothing is left over
        guard let tcpIPPacket1 = try payload1.payload.readTCPIPv4(),
            let tcpIPPacket2 = try payload2.payload.readTCPIPv4()
        else {
            XCTFail("couldn't read TCP/IPv4 packets")
            return
        }
        XCTAssertEqual(1111, tcpIPPacket1.tcpHeader.dstPort)
        XCTAssertEqual(2222, tcpIPPacket1.tcpHeader.srcPort)
        XCTAssertEqual(1111, tcpIPPacket2.tcpHeader.dstPort)
        XCTAssertEqual(2222, tcpIPPacket2.tcpHeader.srcPort)
        let actualData =
            String(decoding: tcpIPPacket1.tcpPayload.readableBytesView, as: Unicode.UTF8.self)
            + String(decoding: tcpIPPacket2.tcpPayload.readableBytesView, as: Unicode.UTF8.self)
        XCTAssertEqual(expectedData, actualData)
    }

    func testOversizedInboundDataComesAsTwoPacketsIPv6() throws {
        self.channel.localAddress = try! SocketAddress(ipAddress: "::1", port: 1111)
        self.channel.remoteAddress = try! SocketAddress(ipAddress: "::2", port: 2222)
        let expectedData = String(repeating: "X", count: Int(UInt16.max) * 2 - 300)
        self.scratchBuffer.writeString(expectedData)
        XCTAssertNoThrow(try self.channel.writeInbound(self.scratchBuffer))
        XCTAssertEqual(1, self.accumulatedPackets.count)

        guard var packetBytes = self.accumulatedPackets.first else {
            XCTFail("couldn't read bytes of first packet")
            return
        }
        guard var payload1 = packetBytes.readPCAPRecord(), var payload2 = packetBytes.readPCAPRecord() else {
            XCTFail("couldn't read payloads from PCAP record")
            return
        }
        XCTAssertEqual(0, packetBytes.readableBytes)  // check nothing is left over
        guard let tcpIPPacket1 = try payload1.payload.readTCPIPv6(),
            let tcpIPPacket2 = try payload2.payload.readTCPIPv6()
        else {
            XCTFail("couldn't read TCP/IPv6 packets")
            return
        }
        XCTAssertEqual(1111, tcpIPPacket1.tcpHeader.dstPort)
        XCTAssertEqual(2222, tcpIPPacket1.tcpHeader.srcPort)
        XCTAssertEqual(1111, tcpIPPacket2.tcpHeader.dstPort)
        XCTAssertEqual(2222, tcpIPPacket2.tcpHeader.srcPort)
        let actualData =
            String(decoding: tcpIPPacket1.tcpPayload.readableBytesView, as: Unicode.UTF8.self)
            + String(decoding: tcpIPPacket2.tcpPayload.readableBytesView, as: Unicode.UTF8.self)
        XCTAssertEqual(expectedData, actualData)
    }

    func testOversizedOutboundDataComesAsTwoPacketsIPv4() throws {
        self.channel.localAddress = try! SocketAddress(ipAddress: "1.2.3.4", port: 1111)
        self.channel.remoteAddress = try! SocketAddress(ipAddress: "9.8.7.6", port: 2222)
        let expectedData = String(repeating: "X", count: Int(UInt16.max) * 2 - 300)
        self.scratchBuffer.writeString(expectedData)
        XCTAssertNoThrow(try self.channel.writeOutbound(self.scratchBuffer))
        XCTAssertEqual(1, self.accumulatedPackets.count)

        guard var packetBytes = self.accumulatedPackets.first else {
            XCTFail("couldn't read bytes of first packet")
            return
        }
        guard var payload1 = packetBytes.readPCAPRecord(), var payload2 = packetBytes.readPCAPRecord() else {
            XCTFail("couldn't read payloads from PCAP record")
            return
        }
        XCTAssertEqual(0, packetBytes.readableBytes)  // check nothing is left over
        guard let tcpIPPacket1 = try payload1.payload.readTCPIPv4(),
            let tcpIPPacket2 = try payload2.payload.readTCPIPv4()
        else {
            XCTFail("couldn't read TCP/IPv4 packets")
            return
        }
        XCTAssertEqual(2222, tcpIPPacket1.tcpHeader.dstPort)
        XCTAssertEqual(1111, tcpIPPacket1.tcpHeader.srcPort)
        XCTAssertEqual(2222, tcpIPPacket2.tcpHeader.dstPort)
        XCTAssertEqual(1111, tcpIPPacket2.tcpHeader.srcPort)
        let actualData =
            String(decoding: tcpIPPacket1.tcpPayload.readableBytesView, as: Unicode.UTF8.self)
            + String(decoding: tcpIPPacket2.tcpPayload.readableBytesView, as: Unicode.UTF8.self)
        XCTAssertEqual(expectedData, actualData)
    }

    func testOversizedOutboundDataComesAsTwoPacketsIPv6() throws {
        self.channel.localAddress = try! SocketAddress(ipAddress: "::1", port: 1111)
        self.channel.remoteAddress = try! SocketAddress(ipAddress: "::2", port: 2222)
        let expectedData = String(repeating: "X", count: Int(UInt16.max) * 2 - 300)
        self.scratchBuffer.writeString(expectedData)
        XCTAssertNoThrow(try self.channel.writeOutbound(self.scratchBuffer))
        XCTAssertEqual(1, self.accumulatedPackets.count)

        guard var packetBytes = self.accumulatedPackets.first else {
            XCTFail("couldn't read bytes of first packet")
            return
        }
        guard var payload1 = packetBytes.readPCAPRecord(), var payload2 = packetBytes.readPCAPRecord() else {
            XCTFail("couldn't read payloads from PCAP record")
            return
        }
        XCTAssertEqual(0, packetBytes.readableBytes)  // check nothing is left over
        guard let tcpIPPacket1 = try payload1.payload.readTCPIPv6(),
            let tcpIPPacket2 = try payload2.payload.readTCPIPv6()
        else {
            XCTFail("couldn't read TCP/IPv6 packets")
            return
        }
        XCTAssertEqual(2222, tcpIPPacket1.tcpHeader.dstPort)
        XCTAssertEqual(1111, tcpIPPacket1.tcpHeader.srcPort)
        XCTAssertEqual(2222, tcpIPPacket2.tcpHeader.dstPort)
        XCTAssertEqual(1111, tcpIPPacket2.tcpHeader.srcPort)
        let actualData =
            String(decoding: tcpIPPacket1.tcpPayload.readableBytesView, as: Unicode.UTF8.self)
            + String(decoding: tcpIPPacket2.tcpPayload.readableBytesView, as: Unicode.UTF8.self)
        XCTAssertEqual(expectedData, actualData)
    }

    func testUnflushedOutboundDataIsNotWritten() throws {
        self.channel.localAddress = try! SocketAddress(ipAddress: "1.2.3.4", port: 1111)
        self.channel.remoteAddress = try! SocketAddress(ipAddress: "9.8.7.6", port: 2222)
        self.scratchBuffer.writeStaticString("hello")
        XCTAssertNoThrow(try self.channel.writeOutbound(self.scratchBuffer))
        self.channel.write(self.scratchBuffer, promise: nil)

        XCTAssertEqual(1, self.accumulatedPackets.count)
        var packet1Bytes = self.accumulatedPackets.first
        XCTAssertNotNil(packet1Bytes?.readPCAPRecord())

        self.channel.flush()
        XCTAssertEqual(2, self.accumulatedPackets.count)
        var packet2Bytes = self.accumulatedPackets.dropFirst().first
        XCTAssertNotNil(packet2Bytes?.readPCAPRecord())
    }

    func testDataWrittenAfterCloseIsDiscarded() throws {
        self.channel.localAddress = try! SocketAddress(ipAddress: "::1", port: 1111)
        self.channel.remoteAddress = try! SocketAddress(ipAddress: "::2", port: 2222)
        self.scratchBuffer.writeStaticString("hello")
        XCTAssertNoThrow(try self.channel.writeOutbound(self.scratchBuffer))
        self.channel.write(self.scratchBuffer, promise: nil)

        XCTAssertEqual(1, self.accumulatedPackets.count)
        var write1Bytes = self.accumulatedPackets.first
        XCTAssertNotNil(write1Bytes?.readPCAPRecord())
        XCTAssertEqual(0, write1Bytes?.readableBytes)  // nothing left

        XCTAssertNoThrow(try self.channel.finish())
        XCTAssertEqual(2, self.accumulatedPackets.count)  // the TCP connection FIN dance
        var write2Bytes = self.accumulatedPackets.dropFirst().first

        let records = [
            write2Bytes?.readPCAPRecord(),  // FIN
            write2Bytes?.readPCAPRecord(),  // FIN+ACK
            write2Bytes?.readPCAPRecord(),  // ACK
        ]
        XCTAssertEqual(0, write2Bytes?.readableBytes)  // nothing left
        var ipPackets: [TCPIPv6Packet] = []
        for var record in records {
            XCTAssertNotNil(record)  // we must have been able to parse a record
            XCTAssertGreaterThan(record?.payload.readableBytes ?? -1, 0)  // there must be some TCP/IP packet in there
            if let ipPacket = try record?.payload.readTCPIPv6() {
                ipPackets.append(ipPacket)
                XCTAssertEqual(0, ipPacket.tcpPayload.readableBytes)
            }
        }

        // FIN, local should be source, remote is destination
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv6Address: ipPackets[0].src,
            actualPort: ipPackets[0].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv6Address: ipPackets[0].dst,
            actualPort: ipPackets[0].tcpHeader.dstPort
        )
        XCTAssertEqual([.fin], ipPackets[0].tcpHeader.flags)
        XCTAssertEqual(20, ipPackets[0].payloadLength)  // 20 -> just the TCP header

        // FIN+ACK, local should be destination, remote should be source
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv6Address: ipPackets[1].src,
            actualPort: ipPackets[1].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv6Address: ipPackets[1].dst,
            actualPort: ipPackets[1].tcpHeader.dstPort
        )
        XCTAssertEqual([.fin, .ack], ipPackets[1].tcpHeader.flags)
        XCTAssertEqual(20, ipPackets[1].payloadLength)  // 20 -> just the TCP header

        // ACK
        self.assertEqual(
            expectedAddress: self.channel?.localAddress,
            actualIPv6Address: ipPackets[0].src,
            actualPort: ipPackets[0].tcpHeader.srcPort
        )
        self.assertEqual(
            expectedAddress: self.channel?.remoteAddress,
            actualIPv6Address: ipPackets[0].dst,
            actualPort: ipPackets[0].tcpHeader.dstPort
        )
        XCTAssertEqual([.ack], ipPackets[2].tcpHeader.flags)
        XCTAssertEqual(20, ipPackets[2].payloadLength)  // 20 -> just the TCP header
    }

    func testUnflushedOutboundDataIsWrittenWhenEmittingWritesOnIssue() throws {
        XCTAssertNoThrow(try self.channel.pipeline.removeHandler(name: "NIOWritePCAPHandler").wait())
        let settings = NIOWritePCAPHandler.Settings(emitPCAPWrites: .whenIssued)
        XCTAssertNoThrow(
            try self.channel.pipeline.syncOperations.addHandler(
                NIOWritePCAPHandler(
                    mode: .client,
                    fakeLocalAddress: nil,
                    fakeRemoteAddress: nil,
                    settings: settings,
                    fileSink: {
                        self.accumulatedPackets.append($0)
                    }
                )
            )
        )
        self.channel.localAddress = try! SocketAddress(ipAddress: "1.2.3.4", port: 1111)
        self.channel.remoteAddress = try! SocketAddress(ipAddress: "9.8.7.6", port: 2222)
        self.scratchBuffer.writeStaticString("hello")
        XCTAssertNoThrow(try self.channel.writeOutbound(self.scratchBuffer))

        // this is unflushed, yet we check it'll still be written because we set `settings.emitPCAPWrites = .whenIssued`
        self.channel.write(self.scratchBuffer, promise: nil)
        XCTAssertEqual(2, self.accumulatedPackets.count)
        var packet1Bytes = self.accumulatedPackets.first
        XCTAssertNotNil(packet1Bytes?.readPCAPRecord())
        var packet2Bytes = self.accumulatedPackets.dropFirst().first
        XCTAssertNotNil(packet2Bytes?.readPCAPRecord())
    }

    func testWeDoNotCrashIfMoreThan4GBOfDataGoThrough() {
        let channel = EmbeddedChannel()
        var numberOfBytesLogged: Int64 = 0

        final class DropAllChannelReads: ChannelInboundHandler {
            typealias InboundIn = ByteBuffer

            func channelRead(context: ChannelHandlerContext, data: NIOAny) {}
        }
        final class DropAllWritesAndFlushes: ChannelOutboundHandler {
            typealias OutboundIn = ByteBuffer

            func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
                promise?.succeed(())
            }

            func flush(context: ChannelHandlerContext) {}
        }

        // Let's drop all writes/flushes so EmbeddedChannel won't accumulate them.
        XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(DropAllWritesAndFlushes()))
        XCTAssertNoThrow(
            try channel.pipeline.syncOperations.addHandler(
                NIOWritePCAPHandler(
                    mode: .client,
                    fakeLocalAddress: .init(ipAddress: "::1", port: 1),
                    fakeRemoteAddress: .init(ipAddress: "::2", port: 2),
                    fileSink: {
                        numberOfBytesLogged += Int64($0.readableBytes)
                    }
                )
            )
        )
        // Let's also drop all channelReads to prevent accumulation of all the data.
        XCTAssertNoThrow(try channel.pipeline.syncOperations.addHandler(DropAllChannelReads()))

        let chunkSize = Int(UInt16.max - 40)  // needs to fit into the IPv4 header which adds 40
        self.scratchBuffer = channel.allocator.buffer(capacity: chunkSize)
        self.scratchBuffer.writeString(String(repeating: "X", count: chunkSize))

        let fourGB: Int64 = 4 * 1024 * 1024 * 1024

        // Let's send 4 GiB inbound, ...
        for _ in 0..<((fourGB / Int64(chunkSize)) + 2) {
            XCTAssertNoThrow(try channel.writeInbound(self.scratchBuffer))
        }
        // ... and 4 GiB outbound.
        for _ in 0..<((fourGB / Int64(chunkSize)) + 2) {
            XCTAssertNoThrow(try channel.writeOutbound(self.scratchBuffer))
        }
        XCTAssertGreaterThan(numberOfBytesLogged, 2 * (fourGB + 1000))
        XCTAssertNoThrow(XCTAssertTrue(try channel.finish().isClean))
    }

}

struct PCAPRecord {
    var time: timeval
    var header: PCAPRecordHeader
    var pcapProtocolID: UInt32
    var payload: ByteBuffer
}

struct TCPIPv4Packet {
    var src: in_addr
    var dst: in_addr
    var wholeIPPacketLength: Int
    var tcpHeader: TCPHeader
    var tcpPayload: ByteBuffer
}

struct TCPIPv6Packet {
    var src: in6_addr
    var dst: in6_addr
    var payloadLength: Int
    var tcpHeader: TCPHeader
    var tcpPayload: ByteBuffer
}

extension ByteBuffer {
    // read & parse a TCP packet, containing everything belonging to it (including payload)
    mutating func readTCPHeader() throws -> TCPHeader? {
        struct ParsingError: Error {}

        let saveSelf = self
        guard let srcPort = self.readInteger(as: UInt16.self),
            let dstPort = self.readInteger(as: UInt16.self),
            let seqNo = self.readInteger(as: UInt32.self),  // seq no
            let ackNo = self.readInteger(as: UInt32.self),  // ack no
            let flagsAndFriends = self.readInteger(as: UInt16.self),  // data offset + reserved bits + fancy stuff
            let _ = self.readInteger(as: UInt16.self),  // window size
            let _ = self.readInteger(as: UInt16.self),  // checksum
            let _ = self.readInteger(as: UInt16.self)  // urgent pointer
        else {
            self = saveSelf
            return nil
        }

        // check that the data offset is right
        guard (flagsAndFriends & (0xf << 12)) == (0x5 << 12) else {
            throw ParsingError()
        }

        return TCPHeader(
            flags: .init(rawValue: UInt8(flagsAndFriends & 0xfff)),
            ackNumber: ackNo == 0 ? nil : ackNo,
            sequenceNumber: seqNo,
            srcPort: srcPort,
            dstPort: dstPort
        )
    }

    // read & parse a TCP/IPv4 packet, containing everything belonging to it (including payload)
    mutating func readTCPIPv4() throws -> TCPIPv4Packet? {
        struct ParsingError: Error {}

        let saveSelf = self
        guard let version = self.readInteger(as: UInt8.self),
            let _ = self.readInteger(as: UInt8.self),  // DSCP
            let ipv4WholeLength = self.readInteger(as: UInt16.self),
            let _ = self.readInteger(as: UInt16.self),  // identification
            let _ = self.readInteger(as: UInt16.self),  // flags & fragment offset
            let _ = self.readInteger(as: UInt8.self),  // TTL
            let innerProtocolID = self.readInteger(as: UInt8.self),  // TCP
            let _ = self.readInteger(as: UInt16.self),  // checksum
            let srcRaw = self.readInteger(endianness: .host, as: UInt32.self),
            let dstRaw = self.readInteger(endianness: .host, as: UInt32.self),
            var payload = self.readSlice(length: Int(ipv4WholeLength - 20)),
            let tcp = try payload.readTCPHeader()
        else {
            self = saveSelf
            return nil
        }
        guard version == 0x45, innerProtocolID == 6 else {  // innerProtocolID -> TCP is 6
            throw ParsingError()
        }

        let src = in_addr(s_addr: srcRaw)
        let dst = in_addr(s_addr: dstRaw)
        return TCPIPv4Packet(
            src: src,
            dst: dst,
            wholeIPPacketLength: .init(ipv4WholeLength),
            tcpHeader: tcp,
            tcpPayload: payload
        )
    }

    // read & parse a TCP/IPv6 packet, containing everything belonging to it (including payload)
    mutating func readTCPIPv6() throws -> TCPIPv6Packet? {
        let saveSelf = self
        guard let versionAndFancyStuff = self.readInteger(as: UInt32.self),  // IP version (6) & fancy stuff
            let payloadLength = self.readInteger(as: UInt16.self),
            let innerProtocolID = self.readInteger(as: UInt8.self),  // TCP
            let _ = self.readInteger(as: UInt8.self),  // hop limit (like TTL)
            var srcAddrBuffer = self.readSlice(length: MemoryLayout<in6_addr>.size),
            var dstAddrBuffer = self.readSlice(length: MemoryLayout<in6_addr>.size),
            var payload = self.readSlice(length: Int(payloadLength)),
            let tcp = try payload.readTCPHeader()
        else {
            self = saveSelf
            return nil
        }
        //                             IPv_6_              TCP is 6
        guard versionAndFancyStuff >> 28 == 6, innerProtocolID == 6 else {
            return nil
        }

        var srcAddress = in6_addr()
        var dstAddress = in6_addr()
        withUnsafeMutableBytes(of: &srcAddress) { copyDestPtr in
            _ = srcAddrBuffer.readWithUnsafeReadableBytes { copySrcPtr in
                precondition(copyDestPtr.count == copySrcPtr.count)
                copyDestPtr.copyMemory(from: copySrcPtr)
                return copyDestPtr.count
            }
        }
        withUnsafeMutableBytes(of: &dstAddress) { copyDestPtr in
            _ = dstAddrBuffer.readWithUnsafeReadableBytes { copySrcPtr in
                precondition(copyDestPtr.count == copySrcPtr.count)
                copyDestPtr.copyMemory(from: copySrcPtr)
                return copyDestPtr.count
            }
        }

        return TCPIPv6Packet(
            src: srcAddress,
            dst: dstAddress,
            payloadLength: .init(payloadLength),
            tcpHeader: tcp,
            tcpPayload: payload
        )
    }

    // read a PCAP record, including all its payload
    mutating func readPCAPRecord() -> PCAPRecord? {
        let saveSelf = self  // save the buffer in case we don't have enough to parse

        guard let timeSecs = self.readInteger(endianness: .host, as: UInt32.self),
            let timeUSecs = self.readInteger(endianness: .host, as: UInt32.self),
            let lenPacket = self.readInteger(endianness: .host, as: UInt32.self),
            let lenDisk = self.readInteger(endianness: .host, as: UInt32.self),
            let pcapProtocolID = self.readInteger(endianness: .host, as: UInt32.self),
            let payload = self.readSlice(length: Int(lenDisk - 4))
        else {
            self = saveSelf
            return nil
        }

        assert(lenPacket == lenDisk, "\(lenPacket) != \(lenDisk)")

        let notImplementedAddress = try! SocketAddress(ipAddress: "9.9.9.9", port: 0xbad)
        let tcp = TCPHeader(flags: [], ackNumber: nil, sequenceNumber: 0xbad, srcPort: 0xbad, dstPort: 0xbad)
        return .init(
            time: timeval(tv_sec: .init(timeSecs), tv_usec: .init(timeUSecs)),
            header: try! PCAPRecordHeader(
                payloadLength: .init(lenPacket),
                src: notImplementedAddress,
                dst: notImplementedAddress,
                tcp: tcp
            ),
            pcapProtocolID: pcapProtocolID,
            payload: payload
        )
    }
}
