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
import Foundation
import Logging
import NIONFS3
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix

struct IAMSorry: Error {
    var because: String
}

@main
struct NIOExtrasNFS3Demo {
    static func main() throws {
        let mount: String? = CommandLine.arguments.dropFirst().first ?? "/tmp/mount"
        let nfsMountTimeoutSeconds = 100
        let nfsMountDeadTimeoutSeconds = 300

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        defer {
            try! group.syncShutdownGracefully()
        }

        let logger = Logger(label: "com.apple.swift-nio-extras-nfs3-demo")

        let server = FileSystemServer(logger: logger)
        try server.start()
        if let mount = mount {
            try server.mount(
                at: mount,
                pathIntoMount: "/",
                nfsMountTimeoutSeconds: nfsMountTimeoutSeconds,
                nfsMountDeadTimeoutSeconds: nfsMountDeadTimeoutSeconds,
                logger: logger
            )
        }

        let waitGroup = DispatchGroup()
        let queue = DispatchQueue(label: "signal queue")
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
        signal(SIGINT, SIG_IGN)
        signalSource.setEventHandler {
            waitGroup.leave()
            _ = signalSource // retaining this here
        }
        signalSource.resume()

        waitGroup.enter()
        waitGroup.notify(queue: DispatchQueue.main) {
            do {
                try server.syncShutdown()
            } catch {
                logger.warning("FileSystemServer shutdown failed", metadata: ["error": "\(error)"])
            }

            logger.info("exiting")
            exit(0)
        }

        RunLoop.main.run()
    }
}
