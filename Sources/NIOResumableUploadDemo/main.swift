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
import System

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
final class UploadServerHandler: ChannelDuplexHandler {
    typealias InboundIn = HTTPRequestPart
    typealias OutboundIn = Never
    typealias OutboundOut = HTTPResponsePart

    let directory: FilePath
    var fileHandle: FileHandle? = nil

    init(directory: FilePath) {
        self.directory = directory
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.unwrapInboundIn(data) {
        case .head(let request):
            switch request.method {
            case .post, .put:
                if let requestPath = request.path {
                    let path = self.directory.appending(requestPath)
                    if let url = URL(path) {
                        FileManager.default.createFile(atPath: path.string, contents: nil)
                        self.fileHandle = try? FileHandle(forWritingTo: url)
                        print("Writing to \(url)")
                    }
                }
                if self.fileHandle == nil {
                    let response = HTTPResponse(status: .internalServerError)
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
            if fileHandle != nil {
                let response = HTTPResponse(status: .created)
                self.write(context: context, data: self.wrapOutboundOut(.head(response)), promise: nil)
                self.write(context: context, data: self.wrapOutboundOut(.end(nil)), promise: nil)
                self.flush(context: context)
            }
        }
    }
}

guard let outputFile = CommandLine.arguments.dropFirst().first else {
    print("Usage: \(CommandLine.arguments[0]) <Upload Directory>")
    exit(1)
}

if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
    let uploadContext = HTTPResumableUploadContext(origin: "http://localhost:8080")

    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    let server = try ServerBootstrap(group: group).childChannelInitializer { channel in
        let handler = HTTP1ToHTTPServerCodec(secure: false)
        return channel.pipeline.addHandlers([
            handler,
            HTTPResumableUploadHandler(
                context: uploadContext,
                handlers: [
                    UploadServerHandler(directory: FilePath(CommandLine.arguments[1]))
                ]
            ),
        ]).flatMap { _ in
            channel.pipeline.configureHTTPServerPipeline(position: .before(handler))
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
