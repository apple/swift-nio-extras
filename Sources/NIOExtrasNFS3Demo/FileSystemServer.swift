//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch
import Logging
import NIONFS3
import NIOCore
import NIOConcurrencyHelpers
import NIOPosix

public final class FileSystemServer: /* self-locked */ @unchecked Sendable {
    private let lock = NIOLock()
    private let logger: Logger

    // all protected with `self.lock`
    private var running = false
    private var mounters: [MountNFS] = []
    private var channel: Channel?
    private var fileSystem: NFS3FileSystemNoAuth?
    private var group: EventLoopGroup?
    private var eventLoop: EventLoop? {
        return self.group?.next()
    }

    public enum Error: Swift.Error {
        case alreadyRunning
        case alreadyShutDown
        case notRunning
    }

    public struct FileSystemInfo {
        public var serverAddress: SocketAddress
        public var fileSystem: NFS3FileSystemNoAuth
    }

    public init(logger: Logger) {
        self.logger = logger
    }

    deinit {
        assert(!self.running, "FileSystemServer deinitialised whilst still running, please call syncShutdown().")
    }

    private func tearEverythingDownLocked() throws {
        var maybeError: Swift.Error? = nil
        assert(!self.running)

        for mounter in self.mounters {
            do {
                try mounter.unmount(logger: self.logger)
            } catch {
                maybeError = error
                logger.warning(
                    "unmount failed",
                    metadata: [
                        "error": "\(error)",
                        "mount-point": "\(mounter.mountPoint)",
                    ])
            }
        }

        do {
            try self.channel?.close().wait()
        } catch {
            maybeError = error
            logger.warning("channel close failed", metadata: ["error": "\(error)"])
        }

        do {
            let shutdownPromise = self.group!.any().makePromise(of: Void.self)
            self.fileSystem!.shutdown(promise: shutdownPromise)
            try shutdownPromise.futureResult.wait()
        } catch {
            maybeError = error
            logger.warning("FileSystem shutdown failed", metadata: ["error": "\(error)"])
        }

        try! self.group?.syncShutdownGracefully()

        if let error = maybeError {
            throw error
        }

        self.group = nil
        self.channel = nil
        self.fileSystem = nil
        self.mounters = []
    }

    public func waitUntilServerFinishes() {
        let g = DispatchGroup()
        g.enter()
        self.lock.withLock {
            if let channel = self.channel {
                channel.closeFuture.whenComplete { _ in
                    g.leave()
                }
            } else {
                g.leave()
            }
        }
        g.wait()
    }

    public func syncShutdown() throws {
        try self.lock.withLock {
            guard self.running else {
                throw Error.alreadyShutDown
            }
            self.running = false

            try self.tearEverythingDownLocked()
        }
    }

    public func mount(
        at mountPoint: String,
        pathIntoMount: String?,
        nfsMountTimeoutSeconds: Int? = nil,
        nfsMountDeadTimeoutSeconds: Int? = nil,
        logger: Logger
    ) throws {
        let mounter = try self.lock.withLock { () throws -> MountNFS in
            guard let localAddress = self.channel?.localAddress else {
                throw Error.notRunning
            }

            let mounter = MountNFS(
                port: localAddress.port!,
                host: localAddress.ipAddress!,
                pathIntoMount: pathIntoMount ?? "/",
                mountPoint: mountPoint,
                nfsMountTimeoutSeconds: nfsMountTimeoutSeconds,
                nfsMountDeadTimeoutSeconds: nfsMountDeadTimeoutSeconds)
            self.mounters.append(mounter)
            return mounter
        }
        try mounter.mount(logger: logger)
    }

    @discardableResult
    public func start(
        serveHost: String = "127.0.0.1",
        servePort: Int? = nil
    ) throws -> FileSystemInfo {
        return try self.lock.withLock { () throws -> FileSystemInfo in
            guard !self.running else {
                throw Error.alreadyRunning
            }

            var connectionID = 0

            self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

            let fileSystem = DummyFS()
            self.fileSystem = fileSystem

            do {
                let channel = try ServerBootstrap(group: self.eventLoop!)
                    .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .childChannelInitializer { channel in
                        self.eventLoop!.assertInEventLoop()

                        connectionID += 1  // not locked but okay because we only have one EventLoop
                        var logger = self.logger
                        let connectionString = """
                            \(connectionID)@\
                            \(channel.remoteAddress?.ipAddress ?? "n/a"):\
                            \(channel.remoteAddress?.port ?? -1)
                            """
                        logger[metadataKey: "tcp-connection"] = "\(connectionString)"
                        return channel.pipeline.addHandlers([
                            NFS3FileSystemServerHandler(
                                fileSystem,
                                logger: logger), /* NOTE: FS is shared here across all channels. */
                            CloseOnErrorHandler(logger: logger),
                        ])
                    }
                    .bind(host: serveHost, port: servePort ?? 0)
                    .wait()
                let channelLocalAddress = channel.localAddress!
                self.logger.info(
                    "FileSystemServer up and running",
                    metadata: [
                        "address": "\(channelLocalAddress)",
                        "pid": "\(getpid())",
                    ])

                self.channel = channel
                self.running = true

                return FileSystemInfo(serverAddress: channelLocalAddress, fileSystem: fileSystem)
            } catch {
                assert(!self.running)

                try? self.tearEverythingDownLocked()

                throw error
            }
        }
    }
}
