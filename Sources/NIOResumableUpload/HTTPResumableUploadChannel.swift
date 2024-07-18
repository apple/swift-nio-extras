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

import Atomics
import NIOCore
import NIOHTTPTypes

/// The child channel that persists across upload resumption attempts, delivering data as if it is
/// a single HTTP upload.
final class HTTPResumableUploadChannel: Channel, ChannelCore {
    let upload: HTTPResumableUpload

    let allocator: ByteBufferAllocator

    private let closePromise: EventLoopPromise<Void>

    var closeFuture: EventLoopFuture<Void> {
        self.closePromise.futureResult
    }

    private var _pipeline: ChannelPipeline!

    var pipeline: ChannelPipeline {
        self._pipeline
    }

    var localAddress: SocketAddress? {
        self.parent?.localAddress
    }

    var remoteAddress: SocketAddress? {
        self.parent?.remoteAddress
    }

    var parent: Channel? {
        self.upload.parentChannel
    }

    var isWritable: Bool {
        self.parent?.isWritable ?? false
    }

    private let _isActiveAtomic: ManagedAtomic<Bool> = .init(true)

    var isActive: Bool {
        self._isActiveAtomic.load(ordering: .relaxed)
    }

    var _channelCore: ChannelCore {
        self
    }

    let eventLoop: EventLoop

    private var autoRead: Bool

    init(
        upload: HTTPResumableUpload,
        parent: Channel,
        channelConfigurator: (Channel) -> Void
    ) {
        self.upload = upload
        self.allocator = parent.allocator
        self.closePromise = parent.eventLoop.makePromise()
        self.eventLoop = parent.eventLoop
        self.autoRead = try! parent.syncOptions!.getOption(ChannelOptions.autoRead)
        self._pipeline = ChannelPipeline(channel: self)
        channelConfigurator(self)
    }

    func setOption<Option>(_ option: Option, value: Option.Value) -> EventLoopFuture<Void> where Option: ChannelOption {
        if self.eventLoop.inEventLoop {
            do {
                return try self.eventLoop.makeSucceededFuture(self.setOption0(option, value: value))
            } catch {
                return self.eventLoop.makeFailedFuture(error)
            }
        } else {
            return self.eventLoop.submit { try self.setOption0(option, value: value) }
        }
    }

    func getOption<Option>(_ option: Option) -> EventLoopFuture<Option.Value> where Option: ChannelOption {
        if self.eventLoop.inEventLoop {
            do {
                return try self.eventLoop.makeSucceededFuture(self.getOption0(option))
            } catch {
                return self.eventLoop.makeFailedFuture(error)
            }
        } else {
            return self.eventLoop.submit { try self.getOption0(option) }
        }
    }

    private func setOption0<Option: ChannelOption>(_ option: Option, value: Option.Value) throws {
        self.eventLoop.preconditionInEventLoop()

        switch option {
        case _ as ChannelOptions.Types.AutoReadOption:
            self.autoRead = value as! Bool
        default:
            if let parent = self.parent {
                try parent.syncOptions!.setOption(option, value: value)
            } else {
                throw HTTPResumableUploadError.parentNotPresent
            }
        }
    }

    private func getOption0<Option: ChannelOption>(_ option: Option) throws -> Option.Value {
        self.eventLoop.preconditionInEventLoop()

        switch option {
        case _ as ChannelOptions.Types.AutoReadOption:
            return self.autoRead as! Option.Value
        default:
            if let parent = self.parent {
                return try parent.syncOptions!.getOption(option)
            } else {
                throw HTTPResumableUploadError.parentNotPresent
            }
        }
    }

    func localAddress0() throws -> SocketAddress {
        fatalError()
    }

    func remoteAddress0() throws -> SocketAddress {
        fatalError()
    }

    func register0(promise: EventLoopPromise<Void>?) {
        fatalError()
    }

    func bind0(to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        fatalError()
    }

    func connect0(to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        fatalError()
    }

    func write0(_ data: NIOAny, promise: EventLoopPromise<Void>?) {
        self.eventLoop.preconditionInEventLoop()
        self.upload.write(unwrapData(data), promise: promise)
    }

    func flush0() {
        self.eventLoop.preconditionInEventLoop()
        self.upload.flush()
    }

    func read0() {
        self.eventLoop.preconditionInEventLoop()
        self.upload.read()
    }

    func close0(error: Error, mode: CloseMode, promise: EventLoopPromise<Void>?) {
        self.eventLoop.preconditionInEventLoop()
        self.upload.close(mode: mode, promise: promise)
    }

    func triggerUserOutboundEvent0(_ event: Any, promise: EventLoopPromise<Void>?) {
        // Do nothing.
    }

    func channelRead0(_ data: NIOAny) {
        // Do nothing.
    }

    func errorCaught0(error: Error) {
        // Do nothing.
    }
}

extension HTTPResumableUploadChannel {
    private struct SynchronousOptions: NIOSynchronousChannelOptions {
        private let channel: HTTPResumableUploadChannel

        init(channel: HTTPResumableUploadChannel) {
            self.channel = channel
        }

        func setOption<Option: ChannelOption>(_ option: Option, value: Option.Value) throws {
            try self.channel.setOption0(option, value: value)
        }

        func getOption<Option: ChannelOption>(_ option: Option) throws -> Option.Value {
            try self.channel.getOption0(option)
        }
    }

    var syncOptions: NIOSynchronousChannelOptions? {
        SynchronousOptions(channel: self)
    }
}

// For `HTTPResumableUpload`.
extension HTTPResumableUploadChannel {
    func start() {
        self.eventLoop.preconditionInEventLoop()
        self.pipeline.fireChannelRegistered()
        self.pipeline.fireChannelActive()
    }

    func receive(_ part: HTTPRequestPart) {
        self.eventLoop.preconditionInEventLoop()
        self.pipeline.fireChannelRead(NIOAny(part))
    }

    func receiveComplete() {
        self.eventLoop.preconditionInEventLoop()
        self.pipeline.fireChannelReadComplete()

        if self.autoRead {
            self.pipeline.read()
        }
    }

    func writabilityChanged() {
        self.eventLoop.preconditionInEventLoop()
        self.pipeline.fireChannelWritabilityChanged()
    }

    func end(error: Error?) {
        self.eventLoop.preconditionInEventLoop()
        if let error {
            self.pipeline.fireErrorCaught(error)
        }
        self._isActiveAtomic.store(false, ordering: .relaxed)
        self.pipeline.fireChannelInactive()
        self.pipeline.fireChannelUnregistered()
        self.eventLoop.execute {
            self.removeHandlers(pipeline: self.pipeline)
            self.closePromise.succeed()
        }
    }
}
