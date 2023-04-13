//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019-2023 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOPosix

public struct NIOPCAPParsingError: Error & Sendable {
    public var problem: String
}

public struct PCAP2Header {
    public var endianness: Endianness
    public let majorVersion: Int = 2
    public var minorVersion: Int
    public var gmtOffset: Int
    public var timestampAccuracy: Int
    public var maximumSnapLength: UInt32
    public var dataLinkType: UInt32

    public init(endianness: Endianness,
                minorVersion: Int,
                gmtOffset: Int,
                timestampAccuracy: Int,
                maximumSnapLength: UInt32,
                dataLinkType: UInt32) {
        self.endianness = endianness
        self.minorVersion = minorVersion
        self.gmtOffset = gmtOffset
        self.timestampAccuracy = timestampAccuracy
        self.maximumSnapLength = maximumSnapLength
        self.dataLinkType = dataLinkType
    }

    public static let `default`: Self = .init(endianness: .host,
                                              minorVersion: 4,
                                              gmtOffset: 0,
                                              timestampAccuracy: .max,
                                              maximumSnapLength: .max,
                                              dataLinkType: 0)
}

public struct PCAPReadError: Error, Hashable {
    private enum ErrorKind: Hashable {
        case invalidMagic
        case unsupportedVersion
    }

    private var errorKind: ErrorKind

    public static let invalidMagic = Self(errorKind: .invalidMagic)
    public static let unsupportedVersion = Self(errorKind: .unsupportedVersion)
}

public struct TCPHeader {
    public struct Flags: OptionSet {
        public var rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let fin = Flags(rawValue: 1 << 0)
        public static let syn = Flags(rawValue: 1 << 1)
        public static let rst = Flags(rawValue: 1 << 2)
        public static let psh = Flags(rawValue: 1 << 3)
        public static let ack = Flags(rawValue: 1 << 4)
        public static let urg = Flags(rawValue: 1 << 5)
        public static let ece = Flags(rawValue: 1 << 6)
        public static let cwr = Flags(rawValue: 1 << 7)
    }

    public var flags: Flags
    public var ackNumber: UInt32?
    public var sequenceNumber: UInt32
    public var srcPort: UInt16
    public var dstPort: UInt16
    public var headerSizeInBytes: UInt8 {
        didSet {
            assert(self.headerSizeInBytes >= 20 && self.headerSizeInBytes <= 60)
        }
    }

    public init(flags: TCPHeader.Flags,
                ackNumber: UInt32? = nil,
                sequenceNumber: UInt32,
                srcPort: UInt16,
                dstPort: UInt16,
                headerSizeInBytes: UInt8 = 20) {
        self.flags = flags
        self.ackNumber = ackNumber
        self.sequenceNumber = sequenceNumber
        self.srcPort = srcPort
        self.dstPort = dstPort
        self.headerSizeInBytes = headerSizeInBytes
        precondition(self.headerSizeInBytes >= 20 && self.headerSizeInBytes <= 60)
    }
}

public struct PCAPRecordHeader {
    public enum Error: Swift.Error {
        case incompatibleAddressPair(SocketAddress, SocketAddress)
    }
    public enum AddressTuple {
        case v4(src: SocketAddress.IPv4Address, dst: SocketAddress.IPv4Address)
        case v6(src: SocketAddress.IPv6Address, dst: SocketAddress.IPv6Address)

        public var srcPort: UInt16 {
            switch self {
            case .v4(src: let src, dst: _):
                return UInt16(bigEndian: src.address.sin_port)
            case .v6(src: let src, dst: _):
                return UInt16(bigEndian: src.address.sin6_port)
            }
        }

        public var dstPort: UInt16 {
            switch self {
            case .v4(src: _, dst: let dst):
                return UInt16(bigEndian: dst.address.sin_port)
            case .v6(src: _, dst: let dst):
                return UInt16(bigEndian: dst.address.sin6_port)
            }
        }
    }

    public var payloadLength: Int
    public var addresses: AddressTuple
    public var time: timeval
    public var tcp: TCPHeader

    public init(payloadLength: Int, addresses: AddressTuple, time: timeval, tcp: TCPHeader) {
        self.payloadLength = payloadLength
        self.addresses = addresses
        self.time = time
        self.tcp = tcp

        assert(addresses.srcPort == Int(tcp.srcPort))
        assert(addresses.dstPort == Int(tcp.dstPort))
        assert(tcp.ackNumber == nil ? !tcp.flags.contains([.ack]) : tcp.flags.contains([.ack]))
    }

    public init(payloadLength: Int, src: SocketAddress, dst: SocketAddress, tcp: TCPHeader) throws {
        let addressTuple: AddressTuple
        switch (src, dst) {
        case (.v4(let src), .v4(let dst)):
            addressTuple = .v4(src: src, dst: dst)
        case (.v6(let src), .v6(let dst)):
            addressTuple = .v6(src: src, dst: dst)
        default:
            throw Error.incompatibleAddressPair(src, dst)
        }
        self = .init(payloadLength: payloadLength, addresses: addressTuple, tcp: tcp)
    }

    public init(payloadLength: Int, addresses: AddressTuple, tcp: TCPHeader) {
        var tv = timeval()
        gettimeofday(&tv, nil)
        self = .init(payloadLength: payloadLength, addresses: addresses, time: tv, tcp: tcp)
    }
}

public struct PCAPRecord {
    public var time: timeval
    public var header: PCAPRecordHeader
    public var pcapProtocolID: UInt32
    public var payload: ByteBuffer

    public init(time: timeval, header: PCAPRecordHeader, pcapProtocolID: UInt32, payload: ByteBuffer) {
        self.time = time
        self.header = header
        self.pcapProtocolID = pcapProtocolID
        self.payload = payload
    }
}

public struct TCPIPv4Packet {
    public var src: in_addr
    public var dst: in_addr
    public var wholeIPPacketLength: Int
    public var tcpHeader: TCPHeader
    public var rawTCPOptions: ByteBuffer
    public var tcpPayload: ByteBuffer

    public init(src: in_addr, dst: in_addr, wholeIPPacketLength: Int, tcpHeader: TCPHeader, rawTCPOptions: ByteBuffer, tcpPayload: ByteBuffer) {
        self.src = src
        self.dst = dst
        self.wholeIPPacketLength = wholeIPPacketLength
        self.tcpHeader = tcpHeader
        self.rawTCPOptions = rawTCPOptions
        self.tcpPayload = tcpPayload
    }
}

public struct TCPIPv6Packet {
    public var src: in6_addr
    public var dst: in6_addr
    public var payloadLength: Int
    public var tcpHeader: TCPHeader
    public var tcpPayload: ByteBuffer

    public init(src: in6_addr, dst: in6_addr, payloadLength: Int, tcpHeader: TCPHeader, tcpPayload: ByteBuffer) {
        self.src = src
        self.dst = dst
        self.payloadLength = payloadLength
        self.tcpHeader = tcpHeader
        self.tcpPayload = tcpPayload
    }
}

extension ByteBuffer {
    // read & parse a TCP packet, containing everything belonging to it (including payload)
    public mutating func readTCPHeader() throws -> TCPHeader? {
        let saveSelf = self
        guard let srcPort = self.readInteger(as: UInt16.self),
            let dstPort = self.readInteger(as: UInt16.self),
            let seqNo = self.readInteger(as: UInt32.self), // seq no
            let ackNo = self.readInteger(as: UInt32.self), // ack no
            let flagsAndFriends = self.readInteger(as: UInt16.self), // data offset + reserved bits + fancy stuff
            let _ = self.readInteger(as: UInt16.self), // window size
            let _ = self.readInteger(as: UInt16.self), // checksum
            let _ = self.readInteger(as: UInt16.self) /* urgent pointer */ else {
                self = saveSelf
                return nil
        }
        let dataOffset = (flagsAndFriends & (0xf << 12)) >> 12
        guard dataOffset >= 5 && dataOffset <= 15 else {
            throw NIOPCAPParsingError(problem: "illegal TCP data offset \(dataOffset)")
        }

        return TCPHeader(flags: .init(rawValue: UInt8(flagsAndFriends & 0xfff)),
                         ackNumber: ackNo == 0 ? nil : ackNo,
                         sequenceNumber: seqNo,
                         srcPort: srcPort,
                         dstPort: dstPort,
                         headerSizeInBytes: UInt8(dataOffset) * 4)
    }

    // read & parse a TCP/IPv4 packet, containing everything belonging to it (including payload)
    public mutating func readTCPIPv4() throws -> TCPIPv4Packet? {
        struct ParsingError: Error {}

        let saveSelf = self
        guard let version = self.readInteger(as: UInt8.self),
            let _ = self.readInteger(as: UInt8.self), // DSCP
            let ipv4WholeLength = self.readInteger(as: UInt16.self),
            let _ = self.readInteger(as: UInt16.self), // identification
            let _ = self.readInteger(as: UInt16.self), // flags & fragment offset
            let _ = self.readInteger(as: UInt8.self), // TTL
            let innerProtocolID = self.readInteger(as: UInt8.self), // TCP
            let _ = self.readInteger(as: UInt16.self), // checksum
            let srcRaw = self.readInteger(endianness: .host, as: UInt32.self),
            let dstRaw = self.readInteger(endianness: .host, as: UInt32.self),
            var payload = self.readSlice(length: Int(ipv4WholeLength - 20)),
            let tcp = try payload.readTCPHeader(),
            let tcpOptions = payload.readSlice(length: Int(tcp.headerSizeInBytes - 20)) else {
                self = saveSelf
                return nil
        }
        guard version == 0x45, innerProtocolID == 6 /* TCP is 6 */ else {
            throw NIOPCAPParsingError(problem: "\(version)/\(innerProtocolID) don't match IPv6")
        }

        let src = in_addr(s_addr: srcRaw)
        let dst = in_addr(s_addr: dstRaw)
        return TCPIPv4Packet(src: src,
                             dst: dst,
                             wholeIPPacketLength: .init(ipv4WholeLength),
                             tcpHeader: tcp,
                             rawTCPOptions: tcpOptions,
                             tcpPayload: payload)
    }

    // read & parse a TCP/IPv6 packet, containing everything belonging to it (including payload)
    public mutating func readTCPIPv6() throws -> TCPIPv6Packet? {
        let saveSelf = self
        guard let versionAndFancyStuff = self.readInteger(as: UInt32.self), // IP version (6) & fancy stuff
            let payloadLength = self.readInteger(as: UInt16.self),
            let innerProtocolID = self.readInteger(as: UInt8.self), // TCP
            let _ = self.readInteger(as: UInt8.self), // hop limit (like TTL)
            var srcAddrBuffer = self.readSlice(length: MemoryLayout<in6_addr>.size),
            var dstAddrBuffer = self.readSlice(length: MemoryLayout<in6_addr>.size),
            var payload = self.readSlice(length: Int(payloadLength)),
            let tcp = try payload.readTCPHeader() else {
                self = saveSelf
                return nil
        }
        guard versionAndFancyStuff >> 28 == 6 /* IPv_6_ */, innerProtocolID == 6 /* TCP is 6 */ else {
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

        return TCPIPv6Packet(src: srcAddress,
                             dst: dstAddress,
                             payloadLength: .init(payloadLength),
                             tcpHeader: tcp,
                             tcpPayload: payload)
    }

    // read a PCAP record, including all its payload
    public mutating func readPCAPRecord(endianness: Endianness = .host) -> PCAPRecord? {
        let saveSelf = self // save the buffer in case we don't have enough to parse

        guard let timeSecs = self.readInteger(endianness: endianness, as: UInt32.self),
            let timeUSecs = self.readInteger(endianness: endianness, as: UInt32.self),
            let lenPacket = self.readInteger(endianness: endianness, as: UInt32.self),
            let lenDisk = self.readInteger(endianness: endianness, as: UInt32.self),
            let pcapProtocolID = self.readInteger(endianness: endianness, as: UInt32.self),
            let payload = self.readSlice(length: Int(lenDisk - 4)) else {
                self = saveSelf
                return nil
        }

        assert(lenPacket == lenDisk, "\(lenPacket) != \(lenDisk)")

        let notImplementedAddress = try! SocketAddress(ipAddress: "9.9.9.9", port: 0xbad)
        let tcp = TCPHeader(flags: [],
                            ackNumber: nil,
                            sequenceNumber: 0xbad,
                            srcPort: 0xbad,
                            dstPort: 0xbad,
                            headerSizeInBytes: 20)
        return .init(time: timeval(tv_sec: .init(timeSecs), tv_usec: .init(timeUSecs)),
                     header: try! PCAPRecordHeader(payloadLength: .init(lenPacket),
                                                   src: notImplementedAddress,
                                                   dst: notImplementedAddress,
                                                   tcp: tcp),
                     pcapProtocolID: pcapProtocolID,
                     payload: payload)
    }
}

extension ByteBuffer {
    mutating func readPCAP2Header() throws -> PCAP2Header? {
        let save = self
        guard let magic = self.readInteger(endianness: .big, as: UInt32.self) else {
            self = save
            return nil
        }

        let wantedMagic: UInt32 = 0xa1b2c3d4
        let endianness: Endianness
        switch magic {
        case wantedMagic:
            endianness = .big
        case UInt32(bigEndian: wantedMagic):
            endianness = .little
        default:
            throw PCAPReadError.invalidMagic
        }

        guard let values = self.readMultipleIntegers(endianness: endianness,
                                                     as: (UInt16, UInt16, UInt32, UInt32, UInt32, UInt32).self) else {
            self = save
            return nil
        }

        let (major, minor, gmtOffset, timestampAccuracy, snapLen, network) = values

        guard major == 2 else {
            throw PCAPReadError.unsupportedVersion
        }

        return PCAP2Header(endianness: endianness,
                           minorVersion: Int(minor),
                           gmtOffset: Int(gmtOffset),
                           timestampAccuracy: Int(timestampAccuracy),
                           maximumSnapLength: snapLen,
                           dataLinkType: network)
    }

    public mutating func writePCAPHeader(_ pcapHeader: PCAP2Header) {
        // guint32 magic_number;   /* magic number */
        self.writeInteger(0xa1b2c3d4, endianness: .host, as: UInt32.self)
        // guint16 version_major;  /* major version number */
        self.writeInteger(UInt16(pcapHeader.majorVersion), endianness: .host, as: UInt16.self)
        // guint16 version_minor;  /* minor version number *
        self.writeInteger(UInt16(pcapHeader.minorVersion), endianness: .host, as: UInt16.self)
        // gint32  thiszone;       /* GMT to local correction */
        self.writeInteger(UInt32(pcapHeader.gmtOffset), endianness: .host, as: UInt32.self)
        // guint32 sigfigs;        /* accuracy of timestamps */
        self.writeInteger(UInt32(truncatingIfNeeded: pcapHeader.timestampAccuracy), endianness: .host, as: UInt32.self)
        // guint32 snaplen;        /* max length of captured packets, in octets */
        self.writeInteger(UInt32(pcapHeader.maximumSnapLength), endianness: .host, as: UInt32.self)
        // guint32 network;        /* data link type */
        self.writeInteger(pcapHeader.dataLinkType, endianness: .host, as: UInt32.self)
    }

    public mutating func writePCAPRecord(_ record: PCAPRecordHeader) throws {
        let rawDataLength = record.payloadLength
        let tcpLength = rawDataLength + 20 /* TCP header length */

        // record
        // guint32 ts_sec;         /* timestamp seconds */
        self.writeInteger(.init(record.time.tv_sec), endianness: .host, as: UInt32.self)
        // guint32 ts_usec;        /* timestamp microseconds */
        self.writeInteger(.init(record.time.tv_usec), endianness: .host, as: UInt32.self)
        // continued below ...

        switch record.addresses {
        case .v4(let la, let ra):
            let ipv4WholeLength = tcpLength + 20 /* IPv4 header length, included in IPv4 */
            let recordLength = ipv4WholeLength + 4 /* 32 bits for protocol id */

            // record, continued
            // guint32 incl_len;       /* number of octets of packet saved in file */
            self.writeInteger(.init(recordLength), endianness: .host, as: UInt32.self)
            // guint32 orig_len;       /* actual length of packet */
            self.writeInteger(.init(recordLength), endianness: .host, as: UInt32.self)

            self.writeInteger(2, endianness: .host, as: UInt32.self) // IPv4

            // IPv4 packet
            self.writeInteger(0x45, as: UInt8.self) // IP version (4) & IHL (5)
            self.writeInteger(0, as: UInt8.self) // DSCP
            self.writeInteger(.init(ipv4WholeLength), as: UInt16.self)

            self.writeInteger(0, as: UInt16.self) // identification
            self.writeInteger(0x4000 /* this set's "don't fragment" */, as: UInt16.self) // flags & fragment offset
            self.writeInteger(.max /* we don't care about TTL */, as: UInt8.self) // TTL
            self.writeInteger(6, as: UInt8.self) // TCP
            self.writeInteger(0, as: UInt16.self) // checksum
            self.writeInteger(la.address.sin_addr.s_addr, endianness: .host, as: UInt32.self)
            self.writeInteger(ra.address.sin_addr.s_addr, endianness: .host, as: UInt32.self)
        case .v6(let la, let ra):
            let ipv6PayloadLength = tcpLength
            let recordLength = ipv6PayloadLength + 4 /* 32 bits for protocol id */ + 40 /* IPv6 header length */

            // record, continued
            // guint32 incl_len;       /* number of octets of packet saved in file */
            self.writeInteger(.init(recordLength), endianness: .host, as: UInt32.self)
            // guint32 orig_len;       /* actual length of packet */
            self.writeInteger(.init(recordLength), endianness: .host, as: UInt32.self)

            self.writeInteger(24, endianness: .host, as: UInt32.self) // IPv6

            // IPv6 packet
            self.writeInteger(/* version */ (6 << 28), as: UInt32.self) // IP version (6) & fancy stuff
            self.writeInteger(.init(ipv6PayloadLength), as: UInt16.self)
            self.writeInteger(6, as: UInt8.self) // TCP
            self.writeInteger(.max /* we don't care about TTL */, as: UInt8.self) // hop limit (like TTL)

            var laAddress = la.address
            withUnsafeBytes(of: &laAddress.sin6_addr) { ptr in
                assert(ptr.count == 16)
                self.writeBytes(ptr)
            }
            var raAddress = ra.address
            withUnsafeBytes(of: &raAddress.sin6_addr) { ptr in
                assert(ptr.count == 16)
                self.writeBytes(ptr)
            }
        }

        // TCP
        self.writeInteger(record.tcp.srcPort, as: UInt16.self)
        self.writeInteger(record.tcp.dstPort, as: UInt16.self)

        self.writeInteger(record.tcp.sequenceNumber, as: UInt32.self) // seq no
        self.writeInteger(record.tcp.ackNumber ?? 0, as: UInt32.self) // ack no

        self.writeInteger(5 << 12 | UInt16(record.tcp.flags.rawValue), as: UInt16.self) // data offset + reserved bits + fancy stuff
        self.writeInteger(.max /* we don't do actual window sizes */, as: UInt16.self) // window size
        self.writeInteger(0xbad /* fake */, as: UInt16.self) // checksum
        self.writeInteger(0, as: UInt16.self) // urgent pointer
    }
}
