//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftNIO project authors
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
    private var uploadHandler: HTTPResumableUploadHandler?
    private let uploadHandlerChannel: NIOLockedValueBox<Channel?> = .init(nil)
    private var uploadChannel: HTTPResumableUploadChannel?

    /// The resumption path containing the unique token identifying the upload.
    private(set) var resumePath: String?
    /// The current upload offset.
    private var offset: Int64 = 0
    /// The total size of the upload (if known).
    private var uploadSize: Int64?
    /// The current request is an upload creation request.
    private var requestIsCreation: Bool = false
    /// The end of the current request is the end of the upload.
    private var requestIsComplete: Bool = true
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

    private func createChannel(handler: HTTPResumableUploadHandler, parent: Channel) -> HTTPResumableUploadChannel {
        let channel = HTTPResumableUploadChannel(
            upload: self,
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

    private func respondAndDetach(_ response: HTTPResponse, handler: HTTPResumableUploadHandler) {
        handler.write(.head(response), promise: nil)
        handler.writeAndFlush(.end(nil), promise: nil)
        if handler === self.uploadHandler {
            detachUploadHandler(close: false)
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

    private func runInEventLoop(_ work: @escaping () -> Void) {
        if self.eventLoop.inEventLoop {
            work()
        } else {
            self.eventLoop.execute(work)
        }
    }

    private func runInEventLoop(checkHandler handler: HTTPResumableUploadHandler, _ work: @escaping () -> Void) {
        self.runInEventLoop {
            if self.uploadHandler === handler {
                work()
            }
        }
    }

    func attachUploadHandler(_ handler: HTTPResumableUploadHandler, channel: Channel) {
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
            if close {
                uploadHandler.close(mode: .all, promise: nil)
            }

            if self.uploadChannel != nil {
                self.idleTimer?.cancel()
                self.idleTimer = self.eventLoop.scheduleTask(in: self.context.timeout) {
                    let error = self.pendingError ?? HTTPResumableUploadError.timeoutWaitingForResumption
                    self.uploadChannel?.end(error: error)
                    self.uploadChannel = nil
                }
            }
        }
    }

    private func offsetRetrieving(otherHandler: HTTPResumableUploadHandler) {
        self.runInEventLoop {
            self.detachUploadHandler(close: true)
            let response = HTTPResumableUploadProtocol.offsetRetrievingResponse(
                offset: self.offset,
                complete: self.uploadComplete
            )
            self.respondAndDetach(response, handler: otherHandler)
        }
    }

    private func uploadAppending(otherHandler: HTTPResumableUploadHandler, channel: Channel, offset: Int64, contentLength: Int64?, complete: Bool) {
        self.runInEventLoop {
            let conflict: Bool
            if self.uploadHandler == nil && self.offset == offset && !self.responseStarted {
                if let uploadSize = self.uploadSize {
                    if let contentLength {
                        conflict = complete && uploadSize != offset + contentLength
                    } else {
                        conflict = true
                    }
                } else {
                    if let contentLength, complete {
                        self.uploadSize = offset + contentLength
                    }
                    conflict = false
                }
            } else {
                conflict = true
            }
            guard !conflict else {
                self.detachUploadHandler(close: true)
                self.destroyChannel(error: HTTPResumableUploadError.badResumption)
                let response = HTTPResumableUploadProtocol.conflictResponse(
                    offset: self.offset,
                    complete: self.uploadComplete
                )
                self.respondAndDetach(response, handler: otherHandler)
                return
            }
            self.requestIsCreation = false
            self.requestIsComplete = complete
            self.attachUploadHandler(otherHandler, channel: channel)
        }
    }

    private func uploadCancellation() {
        self.runInEventLoop {
            self.detachUploadHandler(close: true)
            self.destroyChannel(error: HTTPResumableUploadError.uploadCancelled)
        }
    }

    private func receiveHead(handler: HTTPResumableUploadHandler, channel: Channel, request: HTTPRequest) {
        self.eventLoop.preconditionInEventLoop()

        switch HTTPResumableUploadProtocol.identifyRequest(request, in: self.context) {
        case .notSupported:
            let channel = self.createChannel(handler: handler, parent: channel)
            channel.receive(.head(request))
        case .uploadCreation(let complete, let contentLength):
            self.requestIsCreation = true
            self.requestIsComplete = complete
            self.uploadSize = complete ? contentLength : nil
            let resumePath = self.context.startUpload(self)
            self.resumePath = resumePath

            let informationalResponse = HTTPResumableUploadProtocol.featureDetectionResponse(resumePath: resumePath, in: self.context)
            handler.writeAndFlush(.head(informationalResponse), promise: nil)

            let strippedRequest = HTTPResumableUploadProtocol.stripRequest(request)
            let channel = self.createChannel(handler: handler, parent: channel)
            channel.receive(.head(strippedRequest))
        case .offsetRetrieving:
            if let path = request.path, let upload = self.context.findUpload(path: path) {
                self.uploadHandler = nil
                self.uploadHandlerChannel.withLockedValue { $0 = nil }
                upload.offsetRetrieving(otherHandler: handler)
            } else {
                let response = HTTPResumableUploadProtocol.notFoundResponse()
                self.respondAndDetach(response, handler: handler)
            }
        case .uploadAppending(let offset, let complete, let contentLength):
            if let path = request.path, let upload = self.context.findUpload(path: path) {
                handler.upload = upload
                self.uploadHandler = nil
                self.uploadHandlerChannel.withLockedValue { $0 = nil }
                upload.uploadAppending(otherHandler: handler, channel: channel, offset: offset, contentLength: contentLength, complete: complete)
            } else {
                let response = HTTPResumableUploadProtocol.notFoundResponse()
                self.respondAndDetach(response, handler: handler)
            }
        case .uploadCancellation:
            if let path = request.path, let upload = self.context.findUpload(path: path) {
                upload.uploadCancellation()
                let response = HTTPResumableUploadProtocol.cancelledResponse()
                self.respondAndDetach(response, handler: handler)
            } else {
                let response = HTTPResumableUploadProtocol.notFoundResponse()
                self.respondAndDetach(response, handler: handler)
            }
        case .invalid:
            let response = HTTPResumableUploadProtocol.badRequestResponse()
            self.respondAndDetach(response, handler: handler)
        }
    }

    private func receiveBody(body: ByteBuffer) {
        self.eventLoop.preconditionInEventLoop()

        self.offset += Int64(body.readableBytes)
        self.uploadChannel?.receive(.body(body))
    }

    private func receiveEnd(handler: HTTPResumableUploadHandler, trailers: HTTPFields?) {
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
                    in: self.context
                )
                self.respondAndDetach(response, handler: handler)
            }
        } else {
            self.uploadChannel?.receive(.end(trailers))
        }
    }

    func receive(handler: HTTPResumableUploadHandler, channel: Channel, part: HTTPRequestPart) {
        self.runInEventLoop(checkHandler: handler) {
            switch part {
            case .head(let request):
                self.receiveHead(handler: handler, channel: channel, request: request)
            case .body(let body):
                self.receiveBody(body: body)
            case .end(let trailers):
                self.receiveEnd(handler: handler, trailers: trailers)
            }
        }
    }

    func receiveComplete(handler: HTTPResumableUploadHandler) {
        self.runInEventLoop(checkHandler: handler) {
            self.uploadChannel?.receiveComplete()
        }
    }

    func writabilityChanged(handler: HTTPResumableUploadHandler) {
        self.runInEventLoop(checkHandler: handler) {
            self.uploadChannel?.writabilityChanged()
        }
    }

    func end(handler: HTTPResumableUploadHandler, error: Error?) {
        self.runInEventLoop(checkHandler: handler) {
            if !self.uploadComplete && self.resumePath != nil {
                self.pendingError = error
                self.detachUploadHandler(close: false)
            } else {
                self.destroyChannel(error: error)
                self.detachUploadHandler(close: false)
            }
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
                    in: self.context
                )
                uploadHandler.write(.head(response), promise: promise)
            case .body, .end:
                uploadHandler.write(part, promise: promise)
            }
        } else {
            uploadHandler.write(part, promise: promise)
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
    }
}

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
