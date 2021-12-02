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

#if os(macOS) || os(tvOS) || os(iOS) || os(watchOS)
import Darwin
#else
import Glibc
#endif
import Dispatch

import NIOCore

let sysWrite = write

struct TCPHeader {
    struct Flags: OptionSet {
        var rawValue: UInt8

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        static let fin = Flags(rawValue: 1 << 0)
        static let syn = Flags(rawValue: 1 << 1)
        static let rst = Flags(rawValue: 1 << 2)
        static let psh = Flags(rawValue: 1 << 3)
        static let ack = Flags(rawValue: 1 << 4)
        static let urg = Flags(rawValue: 1 << 5)
        static let ece = Flags(rawValue: 1 << 6)
        static let cwr = Flags(rawValue: 1 << 7)
    }

    var flags: Flags
    var ackNumber: UInt32?
    var sequenceNumber: UInt32
    var srcPort: UInt16
    var dstPort: UInt16
}

struct PCAPRecordHeader {
    enum Error: Swift.Error {
        case incompatibleAddressPair(SocketAddress, SocketAddress)
    }
    enum AddressTuple {
        case v4(src: SocketAddress.IPv4Address, dst: SocketAddress.IPv4Address)
        case v6(src: SocketAddress.IPv6Address, dst: SocketAddress.IPv6Address)

        var srcPort: UInt16 {
            switch self {
            case .v4(src: let src, dst: _):
                return UInt16(bigEndian: src.address.sin_port)
            case .v6(src: let src, dst: _):
                return UInt16(bigEndian: src.address.sin6_port)
            }
        }

        var dstPort: UInt16 {
            switch self {
            case .v4(src: _, dst: let dst):
                return UInt16(bigEndian: dst.address.sin_port)
            case .v6(src: _, dst: let dst):
                return UInt16(bigEndian: dst.address.sin6_port)
            }
        }
    }

    var payloadLength: Int
    var addresses: AddressTuple
    var time: timeval
    var tcp: TCPHeader

    init(payloadLength: Int, addresses: AddressTuple, time: timeval, tcp: TCPHeader) {
        self.payloadLength = payloadLength
        self.addresses = addresses
        self.time = time
        self.tcp = tcp

        assert(addresses.srcPort == Int(tcp.srcPort))
        assert(addresses.dstPort == Int(tcp.dstPort))
        assert(tcp.ackNumber == nil ? !tcp.flags.contains([.ack]) : tcp.flags.contains([.ack]))
    }

    init(payloadLength: Int, src: SocketAddress, dst: SocketAddress, tcp: TCPHeader) throws {
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
    
    init(payloadLength: Int, addresses: AddressTuple, tcp: TCPHeader) {
        var tv = timeval()
        gettimeofday(&tv, nil)
        self = .init(payloadLength: payloadLength, addresses: addresses, time: tv, tcp: tcp)
    }
}

/// A `ChannelHandler` that can write a [`.pcap` file](https://en.wikipedia.org/wiki/Pcap) containing the send/received
/// data as synthesized TCP packet captures.
///
/// You will be able to open the `.pcap` file in for example [Wireshark](https://www.wireshark.org) or
/// [`tcpdump`](http://www.tcpdump.org). Using `NIOWritePCAPHandler` to write your `.pcap` files can be useful for
/// example when your real network traffic is TLS protected (so `tcpdump`/Wireshark can't read it directly), or if you
/// don't have enough privileges on the running host to dump the network traffic.
///
/// `NIOWritePCAPHandler` will also work with Unix Domain Sockets in which case it will still synthesize a TCP packet
/// capture with local address `111.111.111.111` (port `1111`) and remote address `222.222.222.222` (port `2222`).
public class NIOWritePCAPHandler: RemovableChannelHandler {
    public enum Mode {
        case client
        case server
    }

    /// Settings for `NIOWritePCAPHandler`.
    public struct Settings {
        /// When to issue data into the `.pcap` file.
        public enum EmitPCAP {
            /// Write the data immediately when `NIOWritePCAPHandler` saw the event on the `ChannelPipeline`.
            ///
            /// For writes this means when the `write` event is triggered. Please note that this will write potentially
            /// unflushed data into the `.pcap` file.
            ///
            /// If in doubt, prefer `.whenCompleted`.
            case whenIssued

            /// Write the data when the event completed.
            ///
            /// For writes this means when the `write` promise is succeeded. The `whenCompleted` mode mirrors most
            /// closely what's actually sent over the wire.
            case whenCompleted
        }

        /// When to emit the data from the `write` event into the `.pcap` file.
        public var emitPCAPWrites: EmitPCAP

        /// Default settings for the `NIOWritePCAPHandler`.
        public init() {
            self = .init(emitPCAPWrites: .whenCompleted)
        }

        /// Settings with customization.
        ///
        /// - parameters:
        ///    - emitPCAPWrites: When to issue the writes into the `.pcap` file, see `EmitPCAP`.
        public init(emitPCAPWrites: EmitPCAP) {
            self.emitPCAPWrites = emitPCAPWrites
        }
    }

    private enum CloseState {
        case notClosing
        case closedInitiatorLocal
        case closedInitiatorRemote
    }
    
    private let fileSink: (ByteBuffer) -> Void
    private let mode: Mode
    private let maxPayloadSize = Int(UInt16.max - 40 /* needs to fit into the IPv4 header which adds 40 */)
    private let settings: Settings
    private var buffer: ByteBuffer!
    private var readInboundBytes: UInt64 = 0
    private var writtenOutboundBytes: UInt64 = 0
    private var closeState = CloseState.notClosing

    private static let fakeLocalAddress = try! SocketAddress(ipAddress: "111.111.111.111", port: 1111)
    private static let fakeRemoteAddress = try! SocketAddress(ipAddress: "222.222.222.222", port: 2222)
    
    private var localAddress: SocketAddress?
    private var remoteAddress: SocketAddress?

    public static var pcapFileHeader: ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: 24)
        buffer.writePCAPHeader()
        return buffer
    }

    /// Initialize a `NIOWritePCAPHandler`.
    ///
    /// - parameters:
    ///     - fakeLocalAddress: Allows you to optionally override the local address to be different from the real one.
    ///     - fakeRemoteAddress: Allows you to optionally override the remote address to be different from the real one.
    ///     - settings: The settings for the `NIOWritePCAPHandler`.
    ///     - fileSink: The `fileSink` closure is called every time a new chunk of the `.pcap` file is ready to be
    ///                 written to disk or elsewhere. See `SynchronizedFileSink` for a convenient way to write to
    ///                 disk.
    public init(mode: Mode,
                fakeLocalAddress: SocketAddress? = nil,
                fakeRemoteAddress: SocketAddress? = nil,
                settings: Settings,
                fileSink: @escaping (ByteBuffer) -> Void) {
        self.settings = settings
        self.fileSink = fileSink
        self.mode = mode
        if let fakeLocalAddress = fakeLocalAddress {
            self.localAddress = fakeLocalAddress
        }
        if let fakeRemoteAddress = fakeRemoteAddress {
            self.remoteAddress = fakeRemoteAddress
        }
    }

    /// Initialize a `NIOWritePCAPHandler` with default settings.
    ///
    /// - parameters:
    ///     - fakeLocalAddress: Allows you to optionally override the local address to be different from the real one.
    ///     - fakeRemoteAddress: Allows you to optionally override the remote address to be different from the real one.
    ///     - fileSink: The `fileSink` closure is called every time a new chunk of the `.pcap` file is ready to be
    ///                 written to disk or elsewhere. See `NIOSynchronizedFileSink` for a convenient way to write to
    ///                 disk.
    public convenience init(mode: Mode,
                            fakeLocalAddress: SocketAddress? = nil,
                            fakeRemoteAddress: SocketAddress? = nil,
                            fileSink: @escaping (ByteBuffer) -> Void) {
        self.init(mode: mode,
                  fakeLocalAddress: fakeLocalAddress,
                  fakeRemoteAddress: fakeRemoteAddress,
                  settings: Settings(),
                  fileSink: fileSink)
    }
    
    private func writeBuffer(_ buffer: ByteBuffer) {
        self.fileSink(buffer)
    }
    
    private func localAddress(context: ChannelHandlerContext) -> SocketAddress {
        if let localAddress = self.localAddress {
            return localAddress
        } else {
            let localAddress = context.channel.localAddress ?? NIOWritePCAPHandler.fakeLocalAddress
            self.localAddress = localAddress
            return localAddress
        }
    }

    private func remoteAddress(context: ChannelHandlerContext) -> SocketAddress {
        if let remoteAddress = self.remoteAddress {
            return remoteAddress
        } else {
            let remoteAddress = context.channel.remoteAddress ?? NIOWritePCAPHandler.fakeRemoteAddress
            self.remoteAddress = remoteAddress
            return remoteAddress
        }
    }

    private func clientAddress(context: ChannelHandlerContext) -> SocketAddress {
        switch self.mode {
        case .client:
            return self.localAddress(context: context)
        case .server:
            return self.remoteAddress(context: context)
        }
    }

    private func serverAddress(context: ChannelHandlerContext) -> SocketAddress {
        switch self.mode {
        case .client:
            return self.remoteAddress(context: context)
        case .server:
            return self.localAddress(context: context)
        }
    }
    
    private func takeSensiblySizedPayload(buffer: inout ByteBuffer) -> ByteBuffer? {
        guard buffer.readableBytes > 0 else {
            return nil
        }
        
        return buffer.readSlice(length: min(buffer.readableBytes, self.maxPayloadSize))
    }

    private func sequenceNumber(byteCount: UInt64) -> UInt32 {
        return UInt32(byteCount % (UInt64(UInt32.max) + 1))
    }
}

extension NIOWritePCAPHandler: ChannelDuplexHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public typealias OutboundIn = IOData
    public typealias OutboundOut = IOData

    public func handlerAdded(context: ChannelHandlerContext) {
        self.buffer = context.channel.allocator.buffer(capacity: 256)
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        self.buffer.clear()
        self.readInboundBytes = 1
        self.writtenOutboundBytes = 1
        do {
            let clientAddress = self.clientAddress(context: context)
            let serverAddress = self.serverAddress(context: context)
            try self.buffer.writePCAPRecord(.init(payloadLength: 0,
                                                  src: clientAddress,
                                                  dst: serverAddress,
                                                  tcp: TCPHeader(flags: [.syn],
                                                                 ackNumber: nil,
                                                                 sequenceNumber: 0,
                                                                 srcPort: .init(clientAddress.port!),
                                                                 dstPort: .init(serverAddress.port!))))
            try self.buffer.writePCAPRecord(.init(payloadLength: 0,
                                                  src: serverAddress,
                                                  dst: clientAddress,
                                                  tcp: TCPHeader(flags: [.syn, .ack],
                                                                 ackNumber: 1,
                                                                 sequenceNumber: 0,
                                                                 srcPort: .init(serverAddress.port!),
                                                                 dstPort: .init(clientAddress.port!))))
            try self.buffer.writePCAPRecord(.init(payloadLength: 0,
                                                  src: clientAddress,
                                                  dst: serverAddress,
                                                  tcp: TCPHeader(flags: [.ack],
                                                                 ackNumber: 1,
                                                                 sequenceNumber: 1,
                                                                 srcPort: .init(clientAddress.port!),
                                                                 dstPort: .init(serverAddress.port!))))
            self.writeBuffer(self.buffer)
        } catch {
            context.fireErrorCaught(error)
        }
        context.fireChannelActive()
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        let didLocalInitiateTheClose: Bool
        switch self.closeState {
        case .closedInitiatorLocal:
            didLocalInitiateTheClose = true
        case .closedInitiatorRemote:
            didLocalInitiateTheClose = false
        case .notClosing:
            self.closeState = .closedInitiatorRemote
            didLocalInitiateTheClose = false
        }
        
        self.buffer.clear()
        do {
            let closeInitiatorAddress = didLocalInitiateTheClose ? self.localAddress(context: context) : self.remoteAddress(context: context)
            let closeRecipientAddress = didLocalInitiateTheClose ? self.remoteAddress(context: context) : self.localAddress(context: context)
            let initiatorSeq = self.sequenceNumber(byteCount: didLocalInitiateTheClose ?
                                                    self.writtenOutboundBytes : self.readInboundBytes)
            let recipientSeq = self.sequenceNumber(byteCount: didLocalInitiateTheClose ?
                                                    self.readInboundBytes : self.writtenOutboundBytes)
            
            // terminate the connection cleanly
            try self.buffer.writePCAPRecord(.init(payloadLength: 0,
                                                  src: closeInitiatorAddress,
                                                  dst: closeRecipientAddress,
                                                  tcp: TCPHeader(flags: [.fin],
                                                                 ackNumber: nil,
                                                                 sequenceNumber: initiatorSeq,
                                                                 srcPort: .init(closeInitiatorAddress.port!),
                                                                 dstPort: .init(closeRecipientAddress.port!))))
            try self.buffer.writePCAPRecord(.init(payloadLength: 0,
                                                  src: closeRecipientAddress,
                                                  dst: closeInitiatorAddress,
                                                  tcp: TCPHeader(flags: [.ack, .fin],
                                                                 ackNumber: initiatorSeq + 1,
                                                                 sequenceNumber: recipientSeq,
                                                                 srcPort: .init(closeRecipientAddress.port!),
                                                                 dstPort: .init(closeInitiatorAddress.port!))))
            try self.buffer.writePCAPRecord(.init(payloadLength: 0,
                                                  src: closeInitiatorAddress,
                                                  dst: closeRecipientAddress,
                                                  tcp: TCPHeader(flags: [.ack],
                                                                 ackNumber: recipientSeq + 1,
                                                                 sequenceNumber: initiatorSeq + 1,
                                                                 srcPort: .init(closeInitiatorAddress.port!),
                                                                 dstPort: .init(closeRecipientAddress.port!))))
            self.writeBuffer(self.buffer)
        } catch {
            context.fireErrorCaught(error)
        }
        context.fireChannelInactive()
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        defer {
            context.fireChannelRead(data)
        }
        guard self.closeState == .notClosing else {
            return
        }
        
        let data = self.unwrapInboundIn(data)
        guard data.readableBytes > 0 else {
            return
        }
        
        self.buffer.clear()
        do {
            var data = data
            while var payloadToSend = self.takeSensiblySizedPayload(buffer: &data) {
                try self.buffer.writePCAPRecord(.init(payloadLength: payloadToSend.readableBytes,
                                                      src: self.remoteAddress(context: context),
                                                      dst: self.localAddress(context: context),
                                                      tcp: TCPHeader(flags: [],
                                                                     ackNumber: nil,
                                                                     sequenceNumber: self.sequenceNumber(byteCount: self.readInboundBytes),
                                                                     srcPort: .init(self.remoteAddress(context: context).port!),
                                                                     dstPort: .init(self.localAddress(context: context).port!))))
                self.readInboundBytes += UInt64(payloadToSend.readableBytes)
                self.buffer.writeBuffer(&payloadToSend)
            }
            assert(data.readableBytes == 0)
            self.writeBuffer(self.buffer)
        } catch {
            context.fireErrorCaught(error)
        }
    }
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        var buffer = self.unwrapInboundIn(data)

        func emitWrites() {
            do {
                self.buffer.clear()
                while var payloadToSend = self.takeSensiblySizedPayload(buffer: &buffer) {
                    try self.buffer.writePCAPRecord(.init(payloadLength: payloadToSend.readableBytes,
                                                          src: self.localAddress(context: context),
                                                          dst: self.remoteAddress(context: context),
                                                          tcp: TCPHeader(flags: [],
                                                                         ackNumber: nil,
                                                                         sequenceNumber: self.sequenceNumber(byteCount: self.writtenOutboundBytes),
                                                                         srcPort: .init(self.localAddress(context: context).port!),
                                                                         dstPort: .init(self.remoteAddress(context: context).port!))))
                    self.writtenOutboundBytes += UInt64(payloadToSend.readableBytes)
                    self.buffer.writeBuffer(&payloadToSend)
                }
                self.writeBuffer(self.buffer)
            } catch {
                context.fireErrorCaught(error)
            }
        }

        switch self.settings.emitPCAPWrites {
        case .whenCompleted:
            let promise = promise ?? context.eventLoop.makePromise()
            promise.futureResult.whenSuccess {
                emitWrites()
            }
            context.write(data, promise: promise)
        case .whenIssued:
            emitWrites()
            context.write(data, promise: promise)
        }
    }
    
    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent {
            if event == .inputClosed {
                switch self.closeState {
                case .closedInitiatorLocal:
                    () // fair enough, we already closed locally
                case .closedInitiatorRemote:
                    () // that's odd but okay
                case .notClosing:
                    self.closeState = .closedInitiatorRemote
                }
            }
        }
        context.fireUserInboundEventTriggered(event)
    }
    
    public func close(context: ChannelHandlerContext, mode: CloseMode, promise: EventLoopPromise<Void>?) {
        switch self.closeState {
        case .closedInitiatorLocal:
            () // weird, this looks like a double-close
        case .closedInitiatorRemote:
            () // fair enough, already closed I guess
        case .notClosing:
            self.closeState = .closedInitiatorLocal
        }
        context.close(mode: mode, promise: promise)
    }
}

extension ByteBuffer {
    mutating func writePCAPHeader() {
        // guint32 magic_number;   /* magic number */
        self.writeInteger(0xa1b2c3d4, endianness: .host, as: UInt32.self)
        // guint16 version_major;  /* major version number */
        self.writeInteger(2, endianness: .host, as: UInt16.self)
        // guint16 version_minor;  /* minor version number *
        self.writeInteger(4, endianness: .host, as: UInt16.self)
        // gint32  thiszone;       /* GMT to local correction */
        self.writeInteger(0, endianness: .host, as: UInt32.self)
        // guint32 sigfigs;        /* accuracy of timestamps */
        self.writeInteger(0, endianness: .host, as: UInt32.self)
        // guint32 snaplen;        /* max length of captured packets, in octets */
        self.writeInteger(.max, endianness: .host, as: UInt32.self)
        // guint32 network;        /* data link type */
        self.writeInteger(0, endianness: .host, as: UInt32.self)
    }
    
    mutating func writePCAPRecord(_ record: PCAPRecordHeader) throws {
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

extension NIOWritePCAPHandler {
    /// A synchronised file sink that uses a `DispatchQueue` to do all the necessary write synchronously.
    ///
    /// A `SynchronizedFileSink` is thread-safe so can be used from any thread/`EventLoop`. After use, you
    /// _must_ call `syncClose` on the `SynchronizedFileSink` to shut it and all the associated resources down. Failing
    /// to do so triggers undefined behaviour.
    public class SynchronizedFileSink {
        private let fileHandle: NIOFileHandle
        private let workQueue: DispatchQueue
        private let writesGroup = DispatchGroup()
        private let errorHandler: (Swift.Error) -> Void
        private var state: State = .running /* protected by `workQueue` */
        
        public enum FileWritingMode {
            case appendToExistingPCAPFile
            case createNewPCAPFile
        }
        
        public struct Error: Swift.Error {
            public var errorCode: Int
            
            internal enum ErrorCode: Int {
                case cannotOpenFileError = 1
                case cannotWriteToFileError
            }
        }
        
        private enum State {
            case running
            case error(Swift.Error)
        }
        
        /// Creates a `SynchronizedFileSink` for writing to a `.pcap` file at `path`.
        ///
        /// Typically, after you created a `SynchronizedFileSink`, you will hand `myFileSink.write` to
        /// `NIOWritePCAPHandler`'s constructor so `NIOPCAPHandler` can write `.pcap` files. Example:
        ///
        /// ```swift
        /// let fileSink = try NIOWritePCAPHandler.SynchronizedFileSink.fileSinkWritingToFile(path: "test.pcap",
        ///                                                                                   errorHandler: { error in
        ///     print("ERROR: \(error)")
        /// })
        /// defer {
        ///     try fileSink.syncClose()
        /// }
        /// // [...]
        /// channel.pipeline.addHandler(NIOWritePCAPHandler(mode: .server, fileSink: fileSink.write))
        /// ```
        ///
        /// - parameters:
        ///     - path: The path of the `.pcap` file to write.
        ///     - fileWritingMode: Whether to append to an existing `.pcap` file or to create a new `.pcap` file. If you
        ///                        choose to append to an existing `.pcap` file, the file header does not get written.
        ///     - errorHandler: Invoked when an unrecoverable error has occured. In this event you may log the error and
        ///                     you must then `syncClose` the `SynchronizedFileSink`. When `errorHandler` has been
        ///                     called, no further writes will be attempted and `errorHandler` will also not be called
        ///                     again.
        public static func fileSinkWritingToFile(path: String,
                                                 fileWritingMode: FileWritingMode = .createNewPCAPFile,
                                                 errorHandler: @escaping (Swift.Error) -> Void) throws -> SynchronizedFileSink {
            let oflag: CInt = fileWritingMode == FileWritingMode.createNewPCAPFile ? (O_TRUNC | O_CREAT) : O_APPEND
            let fd = try path.withCString { pathPtr -> CInt in
                let fd = open(pathPtr, O_WRONLY | oflag, 0o600)
                guard fd >= 0 else {
                    throw SynchronizedFileSink.Error(errorCode: Error.ErrorCode.cannotOpenFileError.rawValue)
                }
                return fd
            }
            
            if fileWritingMode == .createNewPCAPFile {
                let writeOk = NIOWritePCAPHandler.pcapFileHeader.withUnsafeReadableBytes { ptr in
                    return sysWrite(fd, ptr.baseAddress, ptr.count) == ptr.count
                }
                guard writeOk else {
                    throw SynchronizedFileSink.Error(errorCode: Error.ErrorCode.cannotWriteToFileError.rawValue)
                }
            }
            return SynchronizedFileSink(fileHandle: NIOFileHandle(descriptor: fd),
                                        errorHandler: errorHandler)
        }
        
        private init(fileHandle: NIOFileHandle,
                     errorHandler: @escaping (Swift.Error) -> Void) {
            self.fileHandle = fileHandle
            self.workQueue = DispatchQueue(label: "io.swiftnio.extras.WritePCAPHandler.SynchronizedFileSink.workQueue")
            self.errorHandler = errorHandler
        }
        
        /// Synchronously close this `SynchronizedFileSink` and any associated resources.
        ///
        /// After use, it is mandatory to close a `SynchronizedFileSink` exactly once. `syncClose` may be called from
        /// any thread but not from an `EventLoop` as it will block.
        public func syncClose() throws {
            self.writesGroup.wait()
            try self.workQueue.sync {
                try self.fileHandle.close()
            }
        }
        
        public func write(buffer: ByteBuffer) {
            self.workQueue.async(group: self.writesGroup) {
                guard case .running = self.state else {
                    return
                }
                do {
                    try self.fileHandle.withUnsafeFileDescriptor { fd in
                        var buffer = buffer
                        while buffer.readableBytes > 0 {
                            try buffer.readWithUnsafeReadableBytes { dataPtr in
                                let r = sysWrite(fd, dataPtr.baseAddress, dataPtr.count)
                                assert(r != 0, "write returned 0 but we tried to write \(dataPtr.count) bytes")
                                guard r > 0 else {
                                    throw Error.init(errorCode: Error.ErrorCode.cannotWriteToFileError.rawValue)
                                }
                                return r
                            }
                        }
                    }
                } catch {
                    self.state = .error(error)
                    self.errorHandler(error)
                }
            }
        }
    }
}
