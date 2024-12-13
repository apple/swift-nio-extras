//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2024 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import NIOHTTPResponsiveness
import NIOCore
import NIOHTTPTypesHTTP1
import NIOPosix
import FoundationEssentials

func responsivenessConfigBuffer(scheme: String, host: String, port: Int) throws -> ByteBuffer {
    let cfg = ResponsivenessConfig(
        version: 1,
        urls: ResponsivenessConfigURLs(scheme: scheme, authority: "\(host):\(port)")
    )
    let encoded = try JSONEncoder().encode(cfg)
    return ByteBuffer(bytes: encoded)
}

@main
private struct HTTPResponsivenessServer: ParsableCommand {
    @Option(help: "Which host to bind to")
    var host: String

    @Option(help: "Which port to bind to")
    var port: Int

    func run() throws {
        let config = try responsivenessConfigBuffer(scheme: "http", host: host, port: port)

        let socketBootstrap = ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer({ channel in
                channel.pipeline.configureHTTPServerPipeline().flatMapThrowing {
                    let mux = SimpleResponsivenessRequestMux(responsivenessConfigBuffer: config)
                    return try channel.pipeline.syncOperations.addHandlers([
                        HTTP1ToHTTPServerCodec(secure: false),
                        mux,
                    ])
                }
            })

            // Enable SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)

        let insecureChannel = try socketBootstrap.bind(host: host, port: port).wait()
        print("Listening on http://\(host):\(port)")

        let _ = try insecureChannel.closeFuture.wait()
    }
}
