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

extension NFS3FileSystemNoAuth {
    public func mount(_ call: MountCallMount, eventLoop: EventLoop) -> EventLoopFuture<MountReplyMount> {
        let promise = eventLoop.makePromise(of: MountReplyMount.self)
        if eventLoop.inEventLoop {
            self.mount(call, promise: promise)
        } else {
            eventLoop.execute {
                self.mount(call, promise: promise)
            }
        }
        return promise.futureResult
    }

    public func unmount(_ call: MountCallUnmount, eventLoop: EventLoop) -> EventLoopFuture<MountReplyUnmount> {
        let promise = eventLoop.makePromise(of: MountReplyUnmount.self)
        if eventLoop.inEventLoop {
            self.unmount(call, promise: promise)
        } else {
            eventLoop.execute {
                self.unmount(call, promise: promise)
            }
        }
        return promise.futureResult
    }

    public func getattr(_ call: NFS3CallGetAttr, eventLoop: EventLoop) -> EventLoopFuture<NFS3ReplyGetAttr> {
        let promise = eventLoop.makePromise(of: NFS3ReplyGetAttr.self)
        if eventLoop.inEventLoop {
            self.getattr(call, promise: promise)
        } else {
            eventLoop.execute {
                self.getattr(call, promise: promise)
            }
        }
        return promise.futureResult
    }

    public func fsinfo(_ call: NFS3CallFSInfo, eventLoop: EventLoop) -> EventLoopFuture<NFS3ReplyFSInfo> {
        let promise = eventLoop.makePromise(of: NFS3ReplyFSInfo.self)
        if eventLoop.inEventLoop {
            self.fsinfo(call, promise: promise)
        } else {
            eventLoop.execute {
                self.fsinfo(call, promise: promise)
            }
        }
        return promise.futureResult
    }

    public func pathconf(_ call: NFS3CallPathConf, eventLoop: EventLoop) -> EventLoopFuture<NFS3ReplyPathConf> {
        let promise = eventLoop.makePromise(of: NFS3ReplyPathConf.self)
        if eventLoop.inEventLoop {
            self.pathconf(call, promise: promise)
        } else {
            eventLoop.execute {
                self.pathconf(call, promise: promise)
            }
        }
        return promise.futureResult
    }

    public func fsstat(_ call: NFS3CallFSStat, eventLoop: EventLoop) -> EventLoopFuture<NFS3ReplyFSStat> {
        let promise = eventLoop.makePromise(of: NFS3ReplyFSStat.self)
        if eventLoop.inEventLoop {
            self.fsstat(call, promise: promise)
        } else {
            eventLoop.execute {
                self.fsstat(call, promise: promise)
            }
        }
        return promise.futureResult
    }

    public func access(_ call: NFS3CallAccess, eventLoop: EventLoop) -> EventLoopFuture<NFS3ReplyAccess> {
        let promise = eventLoop.makePromise(of: NFS3ReplyAccess.self)
        if eventLoop.inEventLoop {
            self.access(call, promise: promise)
        } else {
            eventLoop.execute {
                self.access(call, promise: promise)
            }
        }
        return promise.futureResult
    }

    public func lookup(_ call: NFS3CallLookup, eventLoop: EventLoop) -> EventLoopFuture<NFS3ReplyLookup> {
        let promise = eventLoop.makePromise(of: NFS3ReplyLookup.self)
        if eventLoop.inEventLoop {
            self.lookup(call, promise: promise)
        } else {
            eventLoop.execute {
                self.lookup(call, promise: promise)
            }
        }
        return promise.futureResult
    }

    public func readdirplus(_ call: NFS3CallReadDirPlus, eventLoop: EventLoop) -> EventLoopFuture<NFS3ReplyReadDirPlus>
    {
        let promise = eventLoop.makePromise(of: NFS3ReplyReadDirPlus.self)
        if eventLoop.inEventLoop {
            self.readdirplus(call, promise: promise)
        } else {
            eventLoop.execute {
                self.readdirplus(call, promise: promise)
            }
        }
        return promise.futureResult
    }

    public func read(_ call: NFS3CallRead, eventLoop: EventLoop) -> EventLoopFuture<NFS3ReplyRead> {
        let promise = eventLoop.makePromise(of: NFS3ReplyRead.self)
        if eventLoop.inEventLoop {
            self.read(call, promise: promise)
        } else {
            eventLoop.execute {
                self.read(call, promise: promise)
            }
        }
        return promise.futureResult
    }

    public func readlink(_ call: NFS3CallReadlink, eventLoop: EventLoop) -> EventLoopFuture<NFS3ReplyReadlink> {
        let promise = eventLoop.makePromise(of: NFS3ReplyReadlink.self)
        if eventLoop.inEventLoop {
            self.readlink(call, promise: promise)
        } else {
            eventLoop.execute {
                self.readlink(call, promise: promise)
            }
        }
        return promise.futureResult
    }

    public func setattr(_ call: NFS3CallSetattr, eventLoop: EventLoop) -> EventLoopFuture<NFS3ReplySetattr> {
        let promise = eventLoop.makePromise(of: NFS3ReplySetattr.self)
        if eventLoop.inEventLoop {
            self.setattr(call, promise: promise)
        } else {
            eventLoop.execute {
                self.setattr(call, promise: promise)
            }
        }
        return promise.futureResult
    }

    public func shutdown(eventLoop: EventLoop) -> EventLoopFuture<Void> {
        let promise = eventLoop.makePromise(of: Void.self)
        if eventLoop.inEventLoop {
            self.shutdown(promise: promise)
        } else {
            eventLoop.execute {
                self.shutdown(promise: promise)
            }
        }
        return promise.futureResult
    }

    public func readdir(_ call: NFS3CallReadDir, eventLoop: EventLoop) -> EventLoopFuture<NFS3ReplyReadDir> {
        let promise = eventLoop.makePromise(of: NFS3ReplyReadDir.self)
        if eventLoop.inEventLoop {
            self.readdir(call, promise: promise)
        } else {
            eventLoop.execute {
                self.readdir(call, promise: promise)
            }
        }
        return promise.futureResult
    }
}
