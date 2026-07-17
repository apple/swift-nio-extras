//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2025 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import HTTPTypes
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOHTTPTypes
import NIOHTTPTypesHTTP1
import NIOPosix
import NIOResumableUpload
import Testing

final class InMemoryFileStorage: Sendable {
    private let files: NIOLockedValueBox<[String: ByteBuffer]>

    init() {
        self.files = NIOLockedValueBox([:])
    }

    func append(_ bytes: ByteBuffer, forPath path: String) {
        self.files.withLockedValue { files in
            _ = files[path, default: ByteBuffer()].writeImmutableBuffer(bytes)
        }
    }

    func bytes(forPath path: String) -> ByteBuffer? {
        self.files.withLockedValue { $0[path] }
    }
}

final class InMemoryUploadHandler: ChannelDuplexHandler {
    typealias InboundIn = HTTPRequestPart
    typealias OutboundIn = Never
    typealias OutboundOut = HTTPResponsePart

    private let storage: InMemoryFileStorage
    private var currentPath: String?

    init(storage: InMemoryFileStorage) {
        self.storage = storage
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.unwrapInboundIn(data) {
        case .head(let request):
            if let path = request.path {
                self.currentPath = path
            }
        case .body(let body):
            if let path = self.currentPath {
                self.storage.append(body, forPath: path)
            }
        case .end:
            self.currentPath = nil
            let response = HTTPResponse(status: .created)
            context.write(self.wrapOutboundOut(.head(response)), promise: nil)
            context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
            context.flush()
        }
    }
}

enum ResumableUploadError: Error {
    case noResumptionURL
}

final class ClientHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPResponsePart

    private let promise: EventLoopPromise<String?>
    private var resumptionURL: String?

    init(promise: EventLoopPromise<String?>) {
        self.promise = promise
    }

    func channelInactive(context: ChannelHandlerContext) {
        self.promise.fail(ResumableUploadError.noResumptionURL)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.promise.fail(error)
        context.close(promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = self.unwrapInboundIn(data)
        switch part {
        case .head(let response):
            if let location = response.headerFields[.location] {
                self.resumptionURL = location
            }
        case .body:
            ()
        case .end:
            self.promise.succeed(self.resumptionURL)
        }
    }
}

struct NIOResumableUploadE2ETests {
    func withServer(
        origin: String,
        eventLoops: Int,
        body: (
            _ group: any EventLoopGroup,
            _ port: Int,
            _ storage: InMemoryFileStorage
        ) throws -> Void
    ) throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: eventLoops)
        defer { try? group.syncShutdownGracefully() }

        let storage = InMemoryFileStorage()
        let uploadContext = HTTPResumableUploadContext(origin: origin)

        let serverChannel = try ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let sync = channel.pipeline.syncOperations
                    try sync.configureHTTPServerPipeline()
                    try sync.addHandler(HTTP1ToHTTPServerCodec(secure: false))
                    try sync.addHandler(
                        HTTPResumableUploadHandler(
                            context: uploadContext,
                            handlers: [InMemoryUploadHandler(storage: storage)]
                        )
                    )
                }
            }
            .bind(host: "127.0.0.1", port: 0)
            .wait()

        defer {
            try? serverChannel.close().wait()
        }

        let port = try #require(serverChannel.localAddress?.port)
        try body(group, port, storage)
    }

    @Test(
        "Upload split across multiple connections on different event loops",
        arguments: [
            [10],
            [10, 10],
            [10, 7, 5, 3],
            [1, 3, 5, 7],
            [10, 10, 10, 6],
        ]
    )
    func testResumableUploadAcrossEventLoops(chunkSizes: [Int]) throws {
        // Use a handful of threads; we want to exercise the server resuming the upload on
        // different event-loops.
        let origin = "http://localhost"
        try self.withServer(origin: origin, eventLoops: 8) { group, port, storage in
            var chunks = [String]()
            let uploadLength = chunkSizes.reduce(0, +)
            var uploadOffset = 0
            var resumptionPath: String?

            // Upload each chunk
            for (index, chunkSize) in chunkSizes.enumerated() {
                let isFirstChunk = index == 0
                let isLastChunk = index == chunkSizes.count - 1

                // Create the next chunk.
                let character = Character(UnicodeScalar(UInt8(ascii: "a") + UInt8(index % 26)))
                let chunk = String(repeating: character, count: chunkSize)
                chunks.append(chunk)

                // Create new connection for each chunk. The upload location is completed at the end
                // of the response.
                let uploadLoaction = group.next().makePromise(of: String?.self)
                let client = try ClientBootstrap(group: group)
                    .channelInitializer { channel in
                        channel.eventLoop.makeCompletedFuture {
                            let sync = channel.pipeline.syncOperations
                            try sync.addHandler(HTTPRequestEncoder())
                            try sync.addHandler(
                                ByteToMessageHandler(
                                    HTTPResponseDecoder(leftOverBytesStrategy: .dropBytes)
                                )
                            )
                            try sync.addHandler(HTTP1ToHTTPClientCodec())
                            try sync.addHandler(ClientHandler(promise: uploadLoaction))
                        }
                    }
                    .connect(host: "127.0.0.1", port: port)
                    .wait()

                defer {
                    try? client.close().wait()
                }

                let path: String
                let method: HTTPRequest.Method

                if isFirstChunk {
                    path = "/test-file"
                    method = .post
                } else {
                    path = try #require(resumptionPath)
                    method = .patch
                }

                var request = HTTPRequest(
                    method: method,
                    scheme: "http",
                    authority: "localhost",
                    path: path,
                    headerFields: [
                        .uploadDraftInteropVersion: "6",
                        .uploadComplete: isLastChunk ? "?1" : "?0",
                        .uploadLength: "\(uploadLength)",
                        .contentLength: "\(chunkSize)",
                    ]
                )

                if !isFirstChunk {
                    request.headerFields[.uploadOffset] = "\(uploadOffset)"
                    request.headerFields[.contentType] = "application/partial-upload"
                }

                client.write(HTTPRequestPart.head(request), promise: nil)
                client.write(HTTPRequestPart.body(ByteBuffer(string: chunk)), promise: nil)
                client.writeAndFlush(HTTPRequestPart.end(nil), promise: nil)

                // Wait for the response. Non-final chunks should include a resumption URL.
                if isFirstChunk && !isLastChunk {
                    let maybeResumptionURL = try uploadLoaction.futureResult.wait()
                    let resumptionURL = try #require(maybeResumptionURL)
                    resumptionPath = String(resumptionURL.dropFirst(origin.count))
                } else {
                    _ = try uploadLoaction.futureResult.wait()
                }

                uploadOffset += chunkSize
            }

            // Verify the data was stored correctly
            let upload = try #require(storage.bytes(forPath: "/test-file"))
            let expected = chunks.joined(separator: "")
            #expect(String(buffer: upload) == expected)
        }
    }
}

extension HTTPField.Name {
    fileprivate static let uploadDraftInteropVersion = Self("upload-draft-interop-version")!
    fileprivate static let uploadComplete = Self("upload-complete")!
    fileprivate static let uploadOffset = Self("upload-offset")!
    fileprivate static let uploadLength = Self("upload-length")!
}
