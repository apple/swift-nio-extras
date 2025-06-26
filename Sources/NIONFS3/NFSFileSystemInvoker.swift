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

import NIOCore

internal protocol NFS3FileSystemResponder {
    func sendSuccessfulReply(_ reply: NFS3Reply, call: RPCNFS3Call)
    func sendError(_ error: Error, call: RPCNFS3Call)
}

internal struct NFS3FileSystemInvoker<FS: NFS3FileSystemNoAuth, Sink: NFS3FileSystemResponder> {
    private let sink: Sink
    private let fs: FS
    private let eventLoop: EventLoop

    internal init(sink: Sink, fileSystem: FS, eventLoop: EventLoop) {
        self.sink = sink
        self.fs = fileSystem
        self.eventLoop = eventLoop
    }

    func shutdown() -> EventLoopFuture<Void> {
        self.fs.shutdown(eventLoop: self.eventLoop)
    }

    func handleNFS3Call(_ callMessage: RPCNFS3Call) {
        switch callMessage.nfsCall {
        case .mountNull:
            self.sink.sendSuccessfulReply(.mountNull, call: callMessage)
        case .mount(let call):
            self.fs.mount(call, eventLoop: self.eventLoop).assumeIsolated().whenComplete { result in
                switch result {
                case .success(let reply):
                    self.sink.sendSuccessfulReply(.mount(reply), call: callMessage)
                case .failure(let error):
                    self.sink.sendError(error, call: callMessage)
                }
            }
        case .unmount(let call):
            self.fs.unmount(call, eventLoop: self.eventLoop).assumeIsolated().whenComplete { result in
                switch result {
                case .success(let reply):
                    self.sink.sendSuccessfulReply(.unmount(reply), call: callMessage)
                case .failure(let error):
                    self.sink.sendError(error, call: callMessage)
                }
            }
        case .null:
            self.sink.sendSuccessfulReply(.null, call: callMessage)
        case .getattr(let call):
            self.fs.getattr(call, eventLoop: self.eventLoop).assumeIsolated().whenComplete { result in
                switch result {
                case .success(let reply):
                    self.sink.sendSuccessfulReply(.getattr(reply), call: callMessage)
                case .failure(let error):
                    self.sink.sendError(error, call: callMessage)
                }
            }
        case .fsinfo(let call):
            self.fs.fsinfo(call, eventLoop: self.eventLoop).assumeIsolated().whenComplete { result in
                switch result {
                case .success(let reply):
                    self.sink.sendSuccessfulReply(.fsinfo(reply), call: callMessage)
                case .failure(let error):
                    self.sink.sendError(error, call: callMessage)
                }
            }
        case .pathconf(let call):
            self.fs.pathconf(call, eventLoop: self.eventLoop).assumeIsolated().whenComplete { result in
                switch result {
                case .success(let reply):
                    self.sink.sendSuccessfulReply(.pathconf(reply), call: callMessage)
                case .failure(let error):
                    self.sink.sendError(error, call: callMessage)
                }
            }
        case .fsstat(let call):
            self.fs.fsstat(call, eventLoop: self.eventLoop).assumeIsolated().whenComplete { result in
                switch result {
                case .success(let reply):
                    self.sink.sendSuccessfulReply(.fsstat(reply), call: callMessage)
                case .failure(let error):
                    self.sink.sendError(error, call: callMessage)
                }
            }
        case .access(let call):
            self.fs.access(call, eventLoop: self.eventLoop).assumeIsolated().whenComplete { result in
                switch result {
                case .success(let reply):
                    self.sink.sendSuccessfulReply(.access(reply), call: callMessage)
                case .failure(let error):
                    self.sink.sendError(error, call: callMessage)
                }
            }
        case .lookup(let call):
            self.fs.lookup(call, eventLoop: self.eventLoop).assumeIsolated().whenComplete { result in
                switch result {
                case .success(let reply):
                    self.sink.sendSuccessfulReply(.lookup(reply), call: callMessage)
                case .failure(let error):
                    self.sink.sendError(error, call: callMessage)
                }
            }
        case .readdirplus(let call):
            self.fs.readdirplus(call, eventLoop: self.eventLoop).assumeIsolated().whenComplete { result in
                switch result {
                case .success(let reply):
                    self.sink.sendSuccessfulReply(.readdirplus(reply), call: callMessage)
                case .failure(let error):
                    self.sink.sendError(error, call: callMessage)
                }
            }
        case .read(let call):
            self.fs.read(call, eventLoop: self.eventLoop).assumeIsolated().whenComplete { result in
                switch result {
                case .success(let reply):
                    self.sink.sendSuccessfulReply(.read(reply), call: callMessage)
                case .failure(let error):
                    self.sink.sendError(error, call: callMessage)
                }
            }
        case .readdir(let call):
            self.fs.readdir(call, eventLoop: self.eventLoop).assumeIsolated().whenComplete { result in
                switch result {
                case .success(let reply):
                    self.sink.sendSuccessfulReply(.readdir(reply), call: callMessage)
                case .failure(let error):
                    self.sink.sendError(error, call: callMessage)
                }
            }
        case .readlink(let call):
            self.fs.readlink(call, eventLoop: self.eventLoop).assumeIsolated().whenComplete { result in
                switch result {
                case .success(let reply):
                    self.sink.sendSuccessfulReply(.readlink(reply), call: callMessage)
                case .failure(let error):
                    self.sink.sendError(error, call: callMessage)
                }
            }
        case .setattr(let call):
            self.fs.setattr(call, eventLoop: self.eventLoop).assumeIsolated().whenComplete { result in
                switch result {
                case .success(let reply):
                    self.sink.sendSuccessfulReply(.setattr(reply), call: callMessage)
                case .failure(let error):
                    self.sink.sendError(error, call: callMessage)
                }
            }
        case ._PLEASE_DO_NOT_EXHAUSTIVELY_MATCH_THIS_ENUM_NEW_CASES_MIGHT_BE_ADDED_IN_THE_FUTURE:
            // inside the module, matching exhaustively is okay
            preconditionFailure("unknown NFS3 call, this should never happen. Please report a bug.")
        }
    }
}

@available(*, unavailable)
extension NFS3FileSystemInvoker: Sendable {}
