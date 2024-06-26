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

import Foundation
import Logging

public struct MountNFS {
    public let port: Int
    public let host: String
    public let pathIntoMount: String
    public let mountPoint: String
    public let extraOptions: String = ""
    public let nfsAttributeCacheTimeoutSeconds: Int = 3600 * 24 * 365  // 1 year
    public let nfsMountTimeoutSeconds: Int
    public let nfsMountDeadTimeoutSeconds: Int

    public init(
        port: Int,
        host: String,
        pathIntoMount: String,
        mountPoint: String,
        nfsMountTimeoutSeconds: Int? = nil,
        nfsMountDeadTimeoutSeconds: Int? = nil
    ) {
        self.port = port
        self.host = host
        self.pathIntoMount = pathIntoMount
        self.mountPoint = mountPoint
        self.nfsMountTimeoutSeconds = nfsMountTimeoutSeconds ?? 5 * 60
        self.nfsMountDeadTimeoutSeconds = nfsMountDeadTimeoutSeconds ?? 24 * 3600
    }

    func preflightCheck(logger: Logger) throws {
        var logger = logger
        logger[metadataKey: "mount-point"] = "\(self.mountPoint)"

        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: self.mountPoint) {
            logger.notice("mount point does not exist, creating")
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: self.mountPoint),
                withIntermediateDirectories: true)
        }

        guard FileManager.default.fileExists(atPath: self.mountPoint, isDirectory: &isDir) else {
            struct MountPointDoesNotExist: Error {}
            logger.error("even after trying to create it, mount point does not exist")
            throw MountPointDoesNotExist()
        }

        guard isDir.boolValue else {
            struct MountPointNotADirectory: Error {}
            logger.error("mount point not a directory")
            throw MountPointNotADirectory()
        }

        guard try FileManager.default.contentsOfDirectory(atPath: self.mountPoint).count == 0 else {
            struct MountPointNotEmpty: Error {}
            logger.error("mount point not empty")
            throw MountPointNotEmpty()
        }
    }

    public func mount(logger: Logger) throws {
        struct MountFailed: Error {}

        try self.preflightCheck(logger: logger)

        let p = Process()
        #if canImport(Darwin)
        p.executableURL = URL(fileURLWithPath: "/sbin/mount")
        p.arguments = [
            "-o",
            """
            ro,\
            dumbtimer,\
            timeo=\(self.nfsMountTimeoutSeconds),\
            deadtimeout=\(self.nfsMountDeadTimeoutSeconds),\
            port=\(self.port),mountport=\(self.port),\
            acregmin=\(self.nfsAttributeCacheTimeoutSeconds),\
            acregmax=\(self.nfsAttributeCacheTimeoutSeconds),\
            acdirmin=\(self.nfsAttributeCacheTimeoutSeconds),\
            acdirmax=\(self.nfsAttributeCacheTimeoutSeconds),\
            locallocks\
            \(extraOptions.isEmpty ? "" : ",\(self.extraOptions)")
            """,
            "-t", "nfs",
            "\(self.host):/\(self.pathIntoMount)", self.mountPoint,
        ]
        #elseif os(Linux)
        p.executableURL = URL(fileURLWithPath: "/bin/mount")
        p.arguments = [
            "-o",
            // NOTE: timeo is deciseconds on Linux, so 5*60 decaseconds is 30 seconds /shrug
            """
            tcp,\
            timeo=\(self.nfsMountTimeoutSeconds),\
            port=\(self.port),mountport=\(self.port),\
            acregmin=\(self.nfsAttributeCacheTimeoutSeconds),\
            acregmax=\(self.nfsAttributeCacheTimeoutSeconds),\
            acdirmin=\(self.nfsAttributeCacheTimeoutSeconds),\
            acdirmax=\(self.nfsAttributeCacheTimeoutSeconds),\
            local_lock=all,\
            nolock,\
            noacl,rdirplus,\
            ro,\
            nfsvers=3\
            \(extraOptions.isEmpty ? "" : ",\(self.extraOptions)")
            """,
            "-t", "nfs",
            "\(self.host):\(self.pathIntoMount)", self.mountPoint,
        ]
        #endif
        try p.run()
        logger.info(
            "attempting mount",
            metadata: ["mount-command": "\(p.executableURL!.path) \(p.arguments!.joined(separator: " ")) -- "])
        p.waitUntilExit()
        switch (p.terminationReason, p.terminationStatus) {
        case (.exit, 0):
            logger.info("mount successful", metadata: ["mount-point": "\(self.mountPoint)"])
        default:
            logger.error(
                "mount failed",
                metadata: [
                    "termination-reason": "\(p.terminationReason)",
                    "termination-status": "\(p.terminationStatus)",
                ])
            throw MountFailed()
        }
    }

    public func unmount(logger: Logger) throws {
        struct UnMountFailed: Error {}

        let p = Process()
        #if canImport(Darwin)
        p.executableURL = URL(fileURLWithPath: "/sbin/umount")
        #elseif os(Linux)
        p.executableURL = URL(fileURLWithPath: "/bin/umount")
        #endif
        p.arguments = [self.mountPoint]
        try p.run()
        logger.info("attempting unmount", metadata: ["arguments": "\(p.arguments!)"])
        p.waitUntilExit()
        switch (p.terminationReason, p.terminationStatus) {
        case (.exit, 0):
            logger.info("unmount successful")
        default:
            logger.error(
                "unmount failed",
                metadata: [
                    "termination-reason": "\(p.terminationReason)",
                    "termination-status": "\(p.terminationStatus)",
                ])
            throw UnMountFailed()
        }
    }
}
