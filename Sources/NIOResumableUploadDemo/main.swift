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

import Foundation
import HTTPTypes
import NIOCore
import NIOHTTP1
import NIOHTTPTypes
import NIOHTTPTypesHTTP1
import NIOPosix
import NIOResumableUpload

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
final class UploadServerHandler: ChannelDuplexHandler {
    typealias InboundIn = HTTPRequestPart
    typealias OutboundIn = Never
    typealias OutboundOut = HTTPResponsePart

    let directory: URL
    var fileHandle: FileHandle? = nil

    init(directory: URL) {
        self.directory = directory.standardized
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.unwrapInboundIn(data) {
        case .head(let request):
            switch request.method {
            case .post, .put:
                if let path = request.path {
                    let url = self.directory.appendingPathComponent(path, isDirectory: false).standardized
                    if url.path.hasPrefix(self.directory.path) {
                        try? FileManager.default.createDirectory(
                            at: url.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
                        self.fileHandle = try? FileHandle(forWritingTo: url)
                        print("Creating \(url)")
                    }
                }
                if self.fileHandle == nil {
                    let response = HTTPResponse(status: .badRequest)
                    self.write(context: context, data: self.wrapOutboundOut(.head(response)), promise: nil)
                    self.write(context: context, data: self.wrapOutboundOut(.end(nil)), promise: nil)
                    self.flush(context: context)
                }
            default:
                let response = HTTPResponse(status: .notImplemented)
                self.write(context: context, data: self.wrapOutboundOut(.head(response)), promise: nil)
                self.write(context: context, data: self.wrapOutboundOut(.end(nil)), promise: nil)
                self.flush(context: context)
            }
        case .body(let body):
            do {
                try body.withUnsafeReadableBytes { buffer in
                    try fileHandle?.write(contentsOf: buffer)
                }
            } catch {
                print("failed to write \(error)")
                exit(1)
            }
        case .end:
            if let fileHandle = self.fileHandle {
                do {
                    try fileHandle.close()
                    let response = HTTPResponse(status: .created)
                    self.write(context: context, data: self.wrapOutboundOut(.head(response)), promise: nil)
                    self.write(context: context, data: self.wrapOutboundOut(.end(nil)), promise: nil)
                    self.flush(context: context)
                } catch {
                    let response = HTTPResponse(status: .internalServerError)
                    self.write(context: context, data: self.wrapOutboundOut(.head(response)), promise: nil)
                    self.write(context: context, data: self.wrapOutboundOut(.end(nil)), promise: nil)
                    self.flush(context: context)
                }
            }
        }
    }
}

guard let outputFile = CommandLine.arguments.dropFirst().first else {
    print("Usage: \(CommandLine.arguments[0]) <Upload Directory>")
    exit(1)
}

if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
    let uploadContext = HTTPResumableUploadContext(origin: "http://localhost:8081")

    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    let server = try ServerBootstrap(group: group).childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap {
            channel.pipeline.addHandlers([
                HTTP1ToHTTPServerCodec(secure: false),
                HTTPResumableUploadHandler(
                    context: uploadContext,
                    handlers: [
                        UploadServerHandler(directory: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
                    ]
                ),
            ])
        }
    }
    .bind(host: "0.0.0.0", port: 8080)
    .wait()

    print("Listening on 8080")
    try server.closeFuture.wait()
} else {
    print("Unsupported OS")
    exit(1)
}
