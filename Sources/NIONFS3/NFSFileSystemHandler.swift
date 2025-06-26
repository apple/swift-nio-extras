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

/// `ChannelHandler` which implements NFS calls & replies the user implements as a `NFS3FileSystemNoAuth`.
///
/// `NFS3FileSystemNoAuthHandler` is an all-in-one SwiftNIO `ChannelHandler` that implements an NFS3 server. Every call
/// it receives will be forwarded to the user-provided `FS` file system implementation.
///
/// `NFS3FileSystemNoAuthHandler` ignores any [SUN RPC](https://datatracker.ietf.org/doc/html/rfc5531) credentials /
/// verifiers and always replies with `AUTH_NONE`. If you need to implement access control via UNIX user/group, this
/// handler will not be enough. It assumes that every call is allowed. Please note that this is not a security risk
/// because NFS3 traditionally just trusts the UNIX uid/gid that the client provided. So there's no security value
/// added by verifying them. However, the client may rely on the server to check the UNIX permissions (whilst trusting
/// the uid/gid) which cannot be done with this handler.
public final class NFS3FileSystemNoAuthHandler<FS: NFS3FileSystemNoAuth>: ChannelDuplexHandler, NFS3FileSystemResponder
{
    public typealias OutboundIn = Never
    public typealias InboundIn = RPCNFS3Call
    public typealias OutboundOut = RPCNFS3Reply

    private let filesystem: FS
    private let rpcReplySuccess: RPCReplyStatus = .messageAccepted(
        .init(
            verifier: .init(
                flavor: .noAuth,
                opaque: nil
            ),
            status: .success
        )
    )
    private var invoker: NFS3FileSystemInvoker<FS, NFS3FileSystemNoAuthHandler<FS>>?
    private var context: ChannelHandlerContext? = nil

    public init(_ fs: FS) {
        self.filesystem = fs
    }

    public func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        self.invoker = NFS3FileSystemInvoker(sink: self, fileSystem: self.filesystem, eventLoop: context.eventLoop)
    }

    public func handlerRemoved(context: ChannelHandlerContext) {
        self.invoker = nil
        self.context = nil
    }

    func sendSuccessfulReply(_ reply: NFS3Reply, call: RPCNFS3Call) {
        if let context = self.context {
            let reply = RPCNFS3Reply(
                rpcReply: .init(
                    xid: call.rpcCall.xid,
                    status: self.rpcReplySuccess
                ),
                nfsReply: reply
            )
            context.writeAndFlush(self.wrapOutboundOut(reply), promise: nil)
        }
    }

    func sendError(_ error: Error, call: RPCNFS3Call) {
        if let context = self.context {
            let nfsErrorReply = RPCNFS3Reply(
                rpcReply: .init(
                    xid: call.rpcCall.xid,
                    status: self.rpcReplySuccess
                ),
                nfsReply: .mount(
                    .init(
                        result: .fail(
                            .errorSERVERFAULT,
                            NFS3Nothing()
                        )
                    )
                )
            )
            context.writeAndFlush(self.wrapOutboundOut(nfsErrorReply), promise: nil)
            context.fireErrorCaught(error)
        }
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let call = self.unwrapInboundIn(data)
        // ! is safe here because it's set on `handlerAdded` (and unset in `handlerRemoved`). Calling this outside that
        // is programmer error.
        self.invoker!.handleNFS3Call(call)
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        switch error as? NFS3Error {
        case .unknownProgramOrProcedure(.call(let call)):
            let acceptedReply = RPCAcceptedReply(
                verifier: RPCOpaqueAuth(flavor: .noAuth, opaque: nil),
                status: .procedureUnavailable
            )
            let reply = RPCNFS3Reply(
                rpcReply: RPCReply(xid: call.xid, status: .messageAccepted(acceptedReply)),
                nfsReply: .null
            )
            context.writeAndFlush(self.wrapOutboundOut(reply), promise: nil)
            return
        default:
            ()
        }
        context.fireErrorCaught(error)
    }
}

@available(*, unavailable)
extension NFS3FileSystemNoAuthHandler: Sendable {}
