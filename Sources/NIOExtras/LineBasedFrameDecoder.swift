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

///
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
    // we keep track of the last scan end index if we didn't find the delimiter
    private var lastIndex: ByteBufferView.Index? = nil
    
    public init() { }
    
    public func decode(ctx: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        if let frame = try findNextFrame(buffer: &buffer) {
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
        let _endIndex = view.endIndex
        // start where we left off last scan or from the beginning
        let firstIndex = min(self.lastIndex ?? _startIndex, _endIndex)
        view = view.dropFirst(firstIndex)
        while !view.isEmpty {
            if view.starts(with: "\n".utf8) {
                let length = view.startIndex - _startIndex
                // check if the line ends with carriage return, if so drop it
                let dropCarriageReturn = length > 0
                        && buffer.getBytes(at: buffer.readerIndex + length - 1, length: 1) == [0x0D]
                let buff = buffer.readSlice(length: dropCarriageReturn ? length - 1 : length)
                // drop the delimiter (and trailing carriage return if appicable)
                buffer.moveReaderIndex(forwardBy: dropCarriageReturn ? 2 : 1)
                // reset the last scan start index since we found a line
                self.lastIndex = nil
                return buff
            }
            view = view.dropFirst(1)
        }
        // next scan we start where we stopped
        self.lastIndex = max(0, _endIndex - 1)
        return nil
    }
    
    public func handlerRemoved(ctx: ChannelHandlerContext) {
        if let buffer = cumulationBuffer, buffer.readableBytes > 0 {
            ctx.fireErrorCaught(NIOExtrasErrors.LeftOverBytesError(leftOverBytes: buffer))
        }
    }
}
