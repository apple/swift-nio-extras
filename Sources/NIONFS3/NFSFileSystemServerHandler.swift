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

public final class NFS3FileSystemServerHandler<FS: NFS3FileSystemNoAuth> {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    private var error: Error? = nil
    private var b2md = NIOSingleStepByteToMessageProcessor(
        NFS3CallDecoder(),
        maximumBufferSize: 4 * 1024 * 1024
    )
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
    private var invoker: NFS3FileSystemInvoker<FS, NFS3FileSystemServerHandler<FS>>?
    private var context: ChannelHandlerContext? = nil
    private var writeBuffer = ByteBuffer()
    private let fillByteBuffer = ByteBuffer(repeating: 0x41, count: 4)

    public init(_ fs: FS) {
        self.filesystem = fs
    }
}

extension NFS3FileSystemServerHandler: ChannelInboundHandler {
    public func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        self.invoker = NFS3FileSystemInvoker(sink: self, fileSystem: self.filesystem, eventLoop: context.eventLoop)
    }

    public func handlerRemoved(context: ChannelHandlerContext) {
        self.invoker = nil
        self.context = nil
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let data = self.unwrapInboundIn(data)
        guard self.error == nil else {
            context.fireErrorCaught(
                ByteToMessageDecoderError.dataReceivedInErrorState(
                    self.error!,
                    data
                )
            )
            return
        }

        do {
            try self.b2md.process(buffer: data) { nfsCall in
                self.invoker?.handleNFS3Call(nfsCall)
            }
        } catch {
            self.error = error
            self.invoker = nil
            context.fireErrorCaught(error)
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        switch error as? NFS3Error {
        case .unknownProgramOrProcedure(.call(let call)):
            let acceptedReply = RPCAcceptedReply(
                verifier: .init(flavor: .noAuth, opaque: nil),
                status: .procedureUnavailable
            )
            let reply = RPCNFS3Reply(
                rpcReply: RPCReply(xid: call.xid, status: .messageAccepted(acceptedReply)),
                nfsReply: .null
            )
            self.writeBuffer.clear()
            self.writeBuffer.writeRPCNFS3Reply(reply)
            return
        default:
            ()
        }
        context.fireErrorCaught(error)
    }
}

extension NFS3FileSystemServerHandler: NFS3FileSystemResponder {
    func sendSuccessfulReply(_ reply: NFS3Reply, call: RPCNFS3Call) {
        if let context = self.context {
            let reply = RPCNFS3Reply(
                rpcReply: .init(
                    xid: call.rpcCall.xid,
                    status: self.rpcReplySuccess
                ),
                nfsReply: reply
            )

            self.writeBuffer.clear()
            switch self.writeBuffer.writeRPCNFS3ReplyPartially(reply).1 {
            case .doNothing:
                context.writeAndFlush(self.wrapOutboundOut(self.writeBuffer), promise: nil)
            case .writeBlob(let buffer, numberOfFillBytes: let fillBytes):
                context.write(self.wrapOutboundOut(self.writeBuffer), promise: nil)
                context.write(self.wrapOutboundOut(buffer), promise: nil)
                if fillBytes > 0 {
                    var fillers = self.fillByteBuffer
                    context.write(self.wrapOutboundOut(fillers.readSlice(length: fillBytes)!), promise: nil)
                }
                context.flush()
            }
        }
    }

    func sendError(_ error: Error, call: RPCNFS3Call) {
        if let context = self.context {
            let reply = RPCNFS3Reply(
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

            self.writeBuffer.clear()
            self.writeBuffer.writeRPCNFS3Reply(reply)

            context.fireErrorCaught(error)
            context.writeAndFlush(self.wrapOutboundOut(self.writeBuffer), promise: nil)
        }
    }
}

@available(*, unavailable)
extension NFS3FileSystemServerHandler: Sendable {}
