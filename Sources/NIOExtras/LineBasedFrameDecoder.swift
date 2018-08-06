//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO

/// A decoder that splits incoming `ByteBuffer`s around line end
/// character(s) (`'\n'` or `'\r\n'`).
///
/// Let's, for example, consider the following received buffer:
///
///     +----+-------+------------+
///     | AB | C\nDE | F\r\nGHI\n |
///     +----+-------+------------+
///
/// A instance of `LineBasedFrameDecoder` will split this buffer
/// as follows:
///
///     +-----+-----+-----+
///     | ABC | DEF | GHI |
///     +-----+-----+-----+
///
public class LineBasedFrameDecoder: ByteToMessageDecoder {
    
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public var cumulationBuffer: ByteBuffer?
    // keep track of the last scan offset from the buffer's reader index (if we didn't find the delimiter)
    private var lastScanOffset: Int? = nil
    
    public init() { }
    
    public func decode(ctx: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        if let frame = try self.findNextFrame(buffer: &buffer) {
            ctx.fireChannelRead(wrapInboundOut(frame))
            return .continue
        } else {
            return .needMoreData
        }
    }
    
    private func findNextFrame(buffer: inout ByteBuffer) throws -> ByteBuffer? {
        var view = buffer.readableBytesView
        // get the view's true start, end indexes
        let _startIndex = view.startIndex
        // start where we left off or from the beginning
        let lastIndex = self.lastScanOffset.flatMap { buffer.readerIndex + $0 }
        let firstIndex = min(lastIndex ?? _startIndex, view.endIndex)
        view = view.dropFirst(firstIndex - buffer.readerIndex)
        // look for the delimiter
        if let delimiterIndex = view.firstIndex(of: 0x0A) { // '\n'
            let length = delimiterIndex - _startIndex
            let dropCarriageReturn = delimiterIndex > 0 && view[delimiterIndex - 1] == 0x0D // '\r'
            let buff = buffer.readSlice(length: dropCarriageReturn ? length - 1 : length)
            // drop the delimiter (and trailing carriage return if appicable)
            buffer.moveReaderIndex(forwardBy: dropCarriageReturn ? 2 : 1)
            // reset the last scan start index since we found a line
            self.lastScanOffset = nil
            return buff
        }
        // next scan we start where we stopped
        self.lastScanOffset = buffer.readerIndex + view.count
        return nil
    }
    
    public func handlerRemoved(ctx: ChannelHandlerContext) {
        self.handleLeftOverBytes(ctx: ctx)
    }
    
    public func channelInactive(ctx: ChannelHandlerContext) {
        self.handleLeftOverBytes(ctx: ctx)
    }
    
    private func handleLeftOverBytes(ctx: ChannelHandlerContext) {
        if let buffer = cumulationBuffer, buffer.readableBytes > 0 {
            ctx.fireErrorCaught(NIOExtrasErrors.LeftOverBytesError(leftOverBytes: buffer))
        }
    }
}

#if !swift(>=4.2)
private extension ByteBufferView {
    func firstIndex(of: UInt8) -> Int? {
        return self.index(of: of)
    }
}
#endif
