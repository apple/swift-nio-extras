//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the SwiftNIO project authors
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
import NIOHTTPTypes

/// `HTTPResumableUpload` tracks a logical upload. It manages an `HTTPResumableUploadChannel` and
/// connects a series of `HTTPResumableUploadHandler` objects to this channel.
final class HTTPResumableUpload {
    private let context: HTTPResumableUploadContext
    private let channelConfigurator: (Channel) -> Void

    private var eventLoop: EventLoop!
    private var uploadHandler: HTTPResumableUploadHandler.SendableView?
    private let uploadHandlerChannel: NIOLockedValueBox<Channel?> = .init(nil)
    private var uploadChannel: HTTPResumableUploadChannel?

    /// The resumption path containing the unique token identifying the upload.
    private(set) var resumePath: String?
    /// The current upload offset.
    private var offset: Int64 = 0
    /// The total length of the upload (if known).
    private var uploadLength: Int64?
    /// The current request is an upload creation request.
    private var requestIsCreation: Bool = false
    /// The end of the current request is the end of the upload.
    private var requestIsComplete: Bool = true
    /// Whether the request is OPTIONS
    private var requestIsOptions: Bool = false
    /// The interop version of the current request
    private var interopVersion: HTTPResumableUploadProtocol.InteropVersion = .latest
    /// Whether you have received the entire upload.
    private var uploadComplete: Bool = false
    /// The response has started.
    private var responseStarted: Bool = false
    /// The child channel enqueued a read while no upload handler was present.
    private var pendingRead: Bool = false
    /// Last error that the upload handler delivered.
    private var pendingError: Error?
    /// Idle time since the last upload handler detached.
    private var idleTimer: Scheduled<Void>?

    init(
        context: HTTPResumableUploadContext,
        channelConfigurator: @escaping (Channel) -> Void
    ) {
        self.context = context
        self.channelConfigurator = channelConfigurator
    }

    private func createChannel(
        handler: HTTPResumableUploadHandler.SendableView,
        parent: Channel
    ) -> HTTPResumableUploadChannel {
        let channel = HTTPResumableUploadChannel(
            upload: self.sendableView,
            parent: parent,
            channelConfigurator: self.channelConfigurator
        )
        channel.start()
        self.uploadChannel = channel
        return channel
    }

    private func destroyChannel(error: Error?) {
        if let uploadChannel = self.uploadChannel {
            self.context.stopUpload(self)
            self.uploadChannel = nil
            uploadChannel.end(error: error)
        }
    }

    private func respondAndDetach(_ response: HTTPResponse, handler: HTTPResumableUploadHandler.SendableView) {
        handler.withHandler {
            $0.write(.head(response), promise: nil)
            $0.writeAndFlush(.end(nil), promise: nil)
        }

        if handler.id == self.uploadHandler?.id {
            detachUploadHandler(close: false)
        }
    }
}

extension HTTPResumableUpload {
    var sendableView: SendableView {
        SendableView(self)
    }

    struct SendableView: Sendable {
        var eventLoop: any EventLoop { self.loopBoundUpload.eventLoop }
        private let loopBoundUpload: NIOLoopBound<HTTPResumableUpload>
        private let uploadHandlerChannel: NIOLockedValueBox<Channel?>

        init(_ upload: HTTPResumableUpload) {
            self.loopBoundUpload = NIOLoopBound(upload, eventLoop: upload.eventLoop)
            self.uploadHandlerChannel = upload.uploadHandlerChannel
        }

        var assertingCorrectEventLoop: HTTPResumableUpload {
            self.loopBoundUpload.value
        }

        var parentChannel: Channel? {
            self.uploadHandlerChannel.withLockedValue { $0 }
        }

        private func withUploadOnEventLoop(
            expectedID: ObjectIdentifier,
            _ work: @escaping @Sendable (HTTPResumableUpload) -> Void
        ) {
            if self.eventLoop.inEventLoop {
                let upload = self.loopBoundUpload.value
                if upload.uploadHandler?.id == expectedID {
                    work(upload)
                }
            } else {
                self.eventLoop.execute {
                    let upload = self.loopBoundUpload.value
                    if upload.uploadHandler?.id == expectedID {
                        work(upload)
                    }
                }
            }
        }

        private func withUploadOnEventLoop(
            _ work: @escaping @Sendable (HTTPResumableUpload) -> Void
        ) {
            if self.eventLoop.inEventLoop {
                work(self.loopBoundUpload.value)
            } else {
                self.eventLoop.execute {
                    work(self.loopBoundUpload.value)
                }
            }
        }

        func receive(handler: HTTPResumableUploadHandler, channel: Channel, part: HTTPRequestPart) {
            self.withUploadOnEventLoop(expectedID: handler.sendableView.id) { upload in
                switch part {
                case .head(let request):
                    upload.receiveHead(handler: upload.uploadHandler!, channel: channel, request: request)
                case .body(let body):
                    upload.receiveBody(handler: upload.uploadHandler!, body: body)
                case .end(let trailers):
                    upload.receiveEnd(handler: upload.uploadHandler!, trailers: trailers)
                }
            }
        }

        func receiveComplete(handler: HTTPResumableUploadHandler) {
            self.withUploadOnEventLoop(expectedID: handler.sendableView.id) { upload in
                upload.uploadChannel?.receiveComplete()
            }
        }

        func writabilityChanged(handler: HTTPResumableUploadHandler) {
            self.withUploadOnEventLoop(expectedID: handler.sendableView.id) { upload in
                upload.uploadChannel?.writabilityChanged()
            }
        }

        func end(handler: HTTPResumableUploadHandler, error: Error?) {
            self.withUploadOnEventLoop(expectedID: handler.sendableView.id) { upload in
                if !upload.uploadComplete && upload.resumePath != nil {
                    upload.pendingError = error
                    upload.detachUploadHandler(close: false)
                } else {
                    upload.destroyChannel(error: error)
                    upload.detachUploadHandler(close: false)
                }
            }
        }

        func uploadAppending(
            otherHandler: HTTPResumableUploadHandler.SendableView,
            channel: Channel,
            offset: Int64,
            complete: Bool,
            contentLength: Int64?,
            uploadLength: Int64?,
            version: HTTPResumableUploadProtocol.InteropVersion
        ) {
            self.withUploadOnEventLoop { upload in
                upload.uploadAppending(
                    otherHandler: otherHandler,
                    channel: channel,
                    offset: offset,
                    complete: complete,
                    contentLength: contentLength,
                    uploadLength: uploadLength,
                    version: version
                )
            }
        }

        func offsetRetrieving(
            otherHandler: HTTPResumableUploadHandler.SendableView,
            version: HTTPResumableUploadProtocol.InteropVersion
        ) {
            self.withUploadOnEventLoop { upload in
                upload.offsetRetrieving(otherHandler: otherHandler, version: version)
            }
        }

        func uploadCancellation() {
            self.withUploadOnEventLoop { upload in
                upload.uploadCancellation()
            }
        }
    }
}

// For `HTTPResumableUploadHandler`.
extension HTTPResumableUpload {
    /// `HTTPResumableUpload` runs on the same event loop as the initial upload handler that started the upload.
    /// - Parameter eventLoop: The event loop to schedule work in.
    func scheduleOnEventLoop(_ eventLoop: EventLoop) {
        eventLoop.assertInEventLoop()
        assert(self.eventLoop == nil)
        self.eventLoop = eventLoop
    }

    func attachUploadHandler(_ handler: HTTPResumableUploadHandler.SendableView, channel: Channel) {
        self.eventLoop.preconditionInEventLoop()

        self.pendingError = nil
        self.idleTimer?.cancel()
        self.idleTimer = nil

        self.uploadHandler = handler
        self.uploadHandlerChannel.withLockedValue { $0 = channel }
        self.uploadChannel?.writabilityChanged()

        if self.pendingRead {
            self.pendingRead = false
            handler.read()
        }
    }

    private func detachUploadHandler(close: Bool) {
        self.eventLoop.preconditionInEventLoop()

        if let uploadHandler = self.uploadHandler {
            self.uploadHandler = nil
            self.uploadHandlerChannel.withLockedValue { $0 = nil }
            self.uploadChannel?.writabilityChanged()
            uploadHandler.withHandler { handler in
                if close {
                    handler.close(mode: .all, promise: nil)
                }
                handler.detach()
            }

            if self.uploadChannel != nil {
                self.idleTimer?.cancel()
                // Unsafe unchecked is fine: there's a precondition on entering this function.
                self.idleTimer = self.eventLoop.assumeIsolatedUnsafeUnchecked().scheduleTask(in: self.context.timeout) {
                    let error = self.pendingError ?? HTTPResumableUploadError.timeoutWaitingForResumption
                    self.uploadChannel?.end(error: error)
                    self.uploadChannel = nil
                }
            }
        }
    }

    private func offsetRetrieving(
        otherHandler: HTTPResumableUploadHandler.SendableView,
        version: HTTPResumableUploadProtocol.InteropVersion
    ) {
        self.detachUploadHandler(close: true)
        let response = HTTPResumableUploadProtocol.offsetRetrievingResponse(
            offset: self.offset,
            complete: self.uploadComplete,
            version: version
        )
        self.respondAndDetach(response, handler: otherHandler)
    }

    private func saveUploadLength(complete: Bool, contentLength: Int64?, uploadLength: Int64?) -> Bool {
        let computedUploadLength = complete ? contentLength.map { self.offset + $0 } : nil
        if let knownUploadLength = self.uploadLength {
            if let computedUploadLength, knownUploadLength != computedUploadLength {
                return false
            }
        } else {
            self.uploadLength = computedUploadLength
        }
        if let knownUploadLength = self.uploadLength {
            if let uploadLength, knownUploadLength != uploadLength {
                return false
            }
        } else {
            self.uploadLength = uploadLength
        }
        return true
    }

    private func uploadAppending(
        otherHandler: HTTPResumableUploadHandler.SendableView,
        channel: Channel,
        offset: Int64,
        complete: Bool,
        contentLength: Int64?,
        uploadLength: Int64?,
        version: HTTPResumableUploadProtocol.InteropVersion
    ) {
        let conflict: Bool
        if self.uploadHandler == nil && self.offset == offset && !self.responseStarted {
            conflict = !self.saveUploadLength(
                complete: complete,
                contentLength: contentLength,
                uploadLength: uploadLength
            )
        } else {
            conflict = true
        }
        guard !conflict else {
            self.detachUploadHandler(close: true)
            self.destroyChannel(error: HTTPResumableUploadError.badResumption)
            let response = HTTPResumableUploadProtocol.conflictResponse(
                offset: self.offset,
                complete: self.uploadComplete,
                version: version
            )
            self.respondAndDetach(response, handler: otherHandler)
            return
        }
        self.requestIsCreation = false
        self.requestIsComplete = complete
        self.interopVersion = version
        self.attachUploadHandler(otherHandler, channel: channel)
    }

    private func uploadCancellation() {
        self.detachUploadHandler(close: true)
        self.destroyChannel(error: HTTPResumableUploadError.uploadCancelled)
    }

    private func receiveHead(handler: HTTPResumableUploadHandler.SendableView, channel: Channel, request: HTTPRequest) {
        self.eventLoop.preconditionInEventLoop()

        do {
            guard let (type, version) = try HTTPResumableUploadProtocol.identifyRequest(request, in: self.context)
            else {
                let channel = self.createChannel(handler: handler, parent: channel)
                channel.receive(.head(request))
                return
            }
            self.interopVersion = version
            switch type {
            case .uploadCreation(let complete, let contentLength, let uploadLength):
                self.requestIsCreation = true
                self.requestIsComplete = complete
                self.uploadLength = uploadLength
                if !self.saveUploadLength(complete: complete, contentLength: contentLength, uploadLength: uploadLength)
                {
                    let response = HTTPResumableUploadProtocol.conflictResponse(
                        offset: self.offset,
                        complete: self.uploadComplete,
                        version: version
                    )
                    self.respondAndDetach(response, handler: handler)
                    return
                }
                let resumePath = self.context.startUpload(self)
                self.resumePath = resumePath

                let informationalResponse = HTTPResumableUploadProtocol.featureDetectionResponse(
                    resumePath: resumePath,
                    in: self.context,
                    version: version
                )
                handler.writeAndFlush(.head(informationalResponse), promise: nil)

                let strippedRequest = HTTPResumableUploadProtocol.stripRequest(request)
                let channel = self.createChannel(handler: handler, parent: channel)
                channel.receive(.head(strippedRequest))
            case .offsetRetrieving:
                if let path = request.path, let upload = self.context.findUpload(path: path) {
                    self.uploadHandler = nil
                    self.uploadHandlerChannel.withLockedValue { $0 = nil }
                    upload.offsetRetrieving(otherHandler: handler, version: version)
                } else {
                    let response = HTTPResumableUploadProtocol.notFoundResponse(version: version)
                    self.respondAndDetach(response, handler: handler)
                }
            case .uploadAppending(let offset, let complete, let contentLength, let uploadLength):
                if let path = request.path, let upload = self.context.findUpload(path: path) {
                    handler.withHandler { $0.upload = upload }
                    self.uploadHandler = nil
                    self.uploadHandlerChannel.withLockedValue { $0 = nil }
                    upload.uploadAppending(
                        otherHandler: handler,
                        channel: channel,
                        offset: offset,
                        complete: complete,
                        contentLength: contentLength,
                        uploadLength: uploadLength,
                        version: version
                    )
                } else {
                    let response = HTTPResumableUploadProtocol.notFoundResponse(version: version)
                    self.respondAndDetach(response, handler: handler)
                }
            case .uploadCancellation:
                if let path = request.path, let upload = self.context.findUpload(path: path) {
                    upload.uploadCancellation()
                    let response = HTTPResumableUploadProtocol.cancelledResponse(version: version)
                    self.respondAndDetach(response, handler: handler)
                } else {
                    let response = HTTPResumableUploadProtocol.notFoundResponse(version: version)
                    self.respondAndDetach(response, handler: handler)
                }
            case .options:
                self.requestIsOptions = true
                let channel = self.createChannel(handler: handler, parent: channel)
                channel.receive(.head(request))
            }
        } catch {
            let response = HTTPResumableUploadProtocol.badRequestResponse()
            self.respondAndDetach(response, handler: handler)
        }
    }

    private func receiveBody(handler: HTTPResumableUploadHandler.SendableView, body: ByteBuffer) {
        self.eventLoop.preconditionInEventLoop()

        self.offset += Int64(body.readableBytes)

        if let uploadLength = self.uploadLength, self.offset > uploadLength {
            let response = HTTPResumableUploadProtocol.conflictResponse(
                offset: self.offset,
                complete: self.uploadComplete,
                version: self.interopVersion
            )
            self.respondAndDetach(response, handler: handler)
            return
        }
        self.uploadChannel?.receive(.body(body))
    }

    private func receiveEnd(handler: HTTPResumableUploadHandler.SendableView, trailers: HTTPFields?) {
        self.eventLoop.preconditionInEventLoop()

        if let resumePath = self.resumePath {
            if self.requestIsComplete {
                self.uploadComplete = true
                self.uploadChannel?.receive(.end(trailers))
            } else {
                let response = HTTPResumableUploadProtocol.incompleteResponse(
                    offset: self.offset,
                    resumePath: resumePath,
                    forUploadCreation: self.requestIsCreation,
                    in: self.context,
                    version: self.interopVersion
                )
                self.respondAndDetach(response, handler: handler)
            }
        } else {
            self.uploadChannel?.receive(.end(trailers))
        }
    }
}

// For `HTTPResumableUploadChannel`.
extension HTTPResumableUpload {
    var parentChannel: Channel? {
        self.uploadHandlerChannel.withLockedValue { $0 }
    }

    func write(_ part: HTTPResponsePart, promise: EventLoopPromise<Void>?) {
        self.eventLoop.preconditionInEventLoop()

        guard let uploadHandler = self.uploadHandler else {
            promise?.fail(HTTPResumableUploadError.parentNotPresent)
            self.destroyChannel(error: HTTPResumableUploadError.parentNotPresent)
            return
        }

        self.responseStarted = true
        if let resumePath = self.resumePath {
            switch part {
            case .head(let head):
                let response = HTTPResumableUploadProtocol.processResponse(
                    head,
                    offset: self.offset,
                    resumePath: resumePath,
                    forUploadCreation: self.requestIsCreation,
                    in: self.context,
                    version: self.interopVersion
                )
                uploadHandler.write(.head(response), promise: promise)
            case .body, .end:
                uploadHandler.write(part, promise: promise)
            }
        } else {
            if self.requestIsOptions {
                switch part {
                case .head(let head):
                    let response = HTTPResumableUploadProtocol.processOptionsResponse(head)
                    uploadHandler.write(.head(response), promise: promise)
                case .body, .end:
                    uploadHandler.write(part, promise: promise)
                }
            } else {
                uploadHandler.write(part, promise: promise)
            }
        }
    }

    func flush() {
        self.eventLoop.preconditionInEventLoop()

        guard let uploadHandler = self.uploadHandler else {
            self.destroyChannel(error: HTTPResumableUploadError.parentNotPresent)
            return
        }

        uploadHandler.flush()
    }

    func read() {
        self.eventLoop.preconditionInEventLoop()

        if let handler = self.uploadHandler {
            handler.read()
        } else {
            self.pendingRead = true
        }
    }

    func close(mode: CloseMode, promise: EventLoopPromise<Void>?) {
        self.eventLoop.preconditionInEventLoop()

        precondition(mode != .input)
        self.destroyChannel(error: nil)
        self.uploadHandler?.close(mode: mode, promise: promise)
        self.uploadHandler?.detach()
        self.uploadHandler = nil
        self.idleTimer?.cancel()
        self.idleTimer = nil
    }
}

@available(*, unavailable)
extension HTTPResumableUpload: Sendable {}

/// Errors produced by resumable upload.
enum HTTPResumableUploadError: Error {
    /// An upload cancelation request received.
    case uploadCancelled
    /// No upload handler is attached.
    case parentNotPresent
    /// Timed out waiting for an upload handler to attach.
    case timeoutWaitingForResumption
    /// A resumption request from the client is invalid.
    case badResumption
}
