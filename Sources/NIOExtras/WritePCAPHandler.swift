//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019-2022 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch

import NIOCore
import NIOPCAP
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

let sysWrite = write

/// A `ChannelHandler` that can write a [`.pcap` file](https://en.wikipedia.org/wiki/Pcap) containing the send/received
/// data as synthesized TCP packet captures.
///
/// You will be able to open the `.pcap` file in for example [Wireshark](https://www.wireshark.org) or
/// [`tcpdump`](http://www.tcpdump.org). Using `NIOWritePCAPHandler` to write your `.pcap` files can be useful for
/// example when your real network traffic is TLS protected (so `tcpdump`/Wireshark can't read it directly), or if you
/// don't have enough privileges on the running host to dump the network traffic.
///
/// ``NIOWritePCAPHandler`` will also work with Unix Domain Sockets in which case it will still synthesize a TCP packet
/// capture with local address `111.111.111.111` (port `1111`) and remote address `222.222.222.222` (port `2222`).
public class NIOWritePCAPHandler: RemovableChannelHandler {
    public enum Mode {
        case client
        case server
    }

    /// Settings for ``NIOWritePCAPHandler``.
    public struct Settings {
        /// When to issue data into the `.pcap` file.
        public enum EmitPCAP {
            /// Write the data immediately when ``NIOWritePCAPHandler`` saw the event on the `ChannelPipeline`.
            ///
            /// For writes this means when the `write` event is triggered. Please note that this will write potentially
            /// unflushed data into the `.pcap` file.
            ///
            /// If in doubt, prefer ``whenCompleted``.
            case whenIssued

            /// Write the data when the event completed.
            ///
            /// For writes this means when the `write` promise is succeeded. The ``whenCompleted`` mode mirrors most
            /// closely what's actually sent over the wire.
            case whenCompleted
        }

        /// When to emit the data from the `write` event into the `.pcap` file.
        public var emitPCAPWrites: EmitPCAP

        /// Default settings for the ``NIOWritePCAPHandler``.
        public init() {
            self = .init(emitPCAPWrites: .whenCompleted)
        }

        /// Settings with customization.
        ///
        /// - parameters:
        ///    - emitPCAPWrites: When to issue the writes into the `.pcap` file, see ``EmitPCAP``.
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

    /// Reusable header for `.pcap` file.
    public static var pcapFileHeader: ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: 24)
        buffer.writePCAPHeader(.default)
        return buffer
    }

    /// Initialize a ``NIOWritePCAPHandler``.
    ///
    /// - parameters:
    ///     - fakeLocalAddress: Allows you to optionally override the local address to be different from the real one.
    ///     - fakeRemoteAddress: Allows you to optionally override the remote address to be different from the real one.
    ///     - settings: The settings for the ``NIOWritePCAPHandler``.
    ///     - fileSink: The `fileSink` closure is called every time a new chunk of the `.pcap` file is ready to be
    ///                 written to disk or elsewhere. See ``SynchronizedFileSink`` for a convenient way to write to
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

    /// Initialize a ``NIOWritePCAPHandler`` with default settings.
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

#if swift(>=5.6)
@available(*, unavailable)
extension NIOWritePCAPHandler: Sendable {}
#endif

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

extension NIOWritePCAPHandler {
    /// A synchronised file sink that uses a `DispatchQueue` to do all the necessary write synchronously.
    ///
    /// A `SynchronizedFileSink` is thread-safe so can be used from any thread/`EventLoop`. After use, you
    /// _must_ call `syncClose` or `close` on the `SynchronizedFileSink` to shut it and all the associated resources down. Failing
    /// to do so triggers undefined behaviour.
    public final class SynchronizedFileSink {
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

        #if swift(>=5.7)
        /// Synchronously close this `SynchronizedFileSink` and any associated resources.
        ///
        /// After use, it is mandatory to close a `SynchronizedFileSink` exactly once. `syncClose` may be called from
        /// any thread but not from an `EventLoop` as it will block, and may not be called from an async context.
        @available(*, noasync, message: "syncClose() can block indefinitely, prefer close()", renamed: "close()")
        public func syncClose() throws {
            try self._syncClose()
        }
        #else
        /// Synchronously close this `SynchronizedFileSink` and any associated resources.
        ///
        /// After use, it is mandatory to close a `SynchronizedFileSink` exactly once. `syncClose` may be called from
        /// any thread but not from an `EventLoop` as it will block, and may not be called from an async context.
        public func syncClose() throws {
            try self._syncClose()
        }
        #endif

        private func _syncClose() throws {
            self.writesGroup.wait()
            try self.workQueue.sync {
                try self.fileHandle.close()
            }
        }

        /// Close this `SynchronizedFileSink` and any associated resources.
        ///
        /// After use, it is mandatory to close a `SynchronizedFileSink` exactly once.
        @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
        public func close() async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.workQueue.async {
                    continuation.resume(with: Result { try self.fileHandle.close() })
                }
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

extension NIOWritePCAPHandler.SynchronizedFileSink: @unchecked Sendable {}
