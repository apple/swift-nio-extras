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
import NIOExtras

final class WriteAllBytesHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let inFileSink: NIOWritePCAPHandler.SynchronizedFileSink
    private let outFileSink: NIOWritePCAPHandler.SynchronizedFileSink

    init(path: String) {
        self.inFileSink = try! NIOWritePCAPHandler.SynchronizedFileSink.fileSinkWritingToFile(path: path + "-in") {
            error in
            print("ERROR (\(#line)): \(error)")
        }
        self.outFileSink = try! NIOWritePCAPHandler.SynchronizedFileSink.fileSinkWritingToFile(path: path + "-out") {
            error in
            print("ERROR (\(#line)): \(error)")
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.fireChannelRead(data)

        let buffer = self.unwrapInboundIn(data)
        self.inFileSink.write(buffer: buffer)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        context.write(data, promise: promise)

        let buffer = self.unwrapOutboundIn(data)
        self.outFileSink.write(buffer: buffer)
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        try! self.inFileSink.syncClose()
        try! self.outFileSink.syncClose()
    }
}
