//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019-2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

extension NIOJSONRPCFraming {
    /// `ContentLengthHeaderFrameEncoder` is responsible for emitting JSON-RPC wire protocol with 'Content-Length'
    /// HTTP-like headers as used by for example by LSP (Language Server Protocol).
    public final class ContentLengthHeaderFrameEncoder: ChannelOutboundHandler {
        /// We'll get handed one message through the `Channel` and ...
        public typealias OutboundIn = ByteBuffer
        /// ... will encode it into a `ByteBuffer`.
        public typealias OutboundOut = ByteBuffer

        private var scratchBuffer: ByteBuffer!

        public init() {}

        public func handlerAdded(context: ChannelHandlerContext) {
            self.scratchBuffer = context.channel.allocator.buffer(capacity: 512)
        }

        public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
            let data = self.unwrapOutboundIn(data)
            // Step 1, clear the target buffer (note, we are re-using it so if we get lucky we don't need to
            // allocate at all.
            self.scratchBuffer.clear()

            // Step 2, write the wire protocol for the header.
            self.scratchBuffer.writeStaticString("Content-Length: ")
            self.scratchBuffer.writeString(String(data.readableBytes, radix: 10))
            self.scratchBuffer.writeStaticString("\r\n\r\n")

            // Step 3, send header and the raw message through the `Channel`.
            if data.readableBytes > 0 {
                context.write(self.wrapOutboundOut(self.scratchBuffer), promise: nil)
                context.write(self.wrapOutboundOut(data), promise: promise)
            } else {
                context.write(self.wrapOutboundOut(self.scratchBuffer), promise: promise)
            }
        }
    }

    /// `ContentLengthHeaderFrameDecoder` is responsible for parsing JSON-RPC wire protocol with 'Content-Length'
    /// HTTP-like headers as used by for example by LSP (Language Server Protocol).
    public struct ContentLengthHeaderFrameDecoder: ByteToMessageDecoder {
        /// We're emitting one `ByteBuffer` corresponding exactly to one full payload, no headers etc.
        public typealias InboundOut = ByteBuffer

        /// `ContentLengthHeaderFrameDecoder` is a simple state machine.
        private enum State {
            /// either we're waiting for the end of the header block or a new header field, ...
            case waitingForHeaderNameOrHeaderBlockEnd
            /// ... or for a header value, or ...
            case waitingForHeaderValue(name: String)
            /// ... or for the payload of a given size.
            case waitingForPayload(length: Int)
        }

        /// A `DecodingError` is sent through the pipeline if anything went wrong.
        public enum DecodingError: Error, Equatable {
            /// Missing 'Content-Length' header.
            case missingContentLengthHeader

            /// The value of the 'Content-Length' header was illegal, for example a negative number.
            case illegalContentLengthHeaderValue(String)
        }

        public init() {}

        // We start waiting for a header field (or the end of a header block).
        private var state: State = .waitingForHeaderNameOrHeaderBlockEnd
        private var payloadLength: Int? = nil

        // Finishes a header block, most of the time that's very straighforward but we need to verify a few
        // things here.
        private mutating func processHeaderBlockEnd(context: ChannelHandlerContext) throws -> DecodingState {
            if let payloadLength = self.payloadLength {
                if payloadLength == 0 {
                    // special case, we're not actually waiting for anything if it's 0 bytes...
                    self.state = .waitingForHeaderNameOrHeaderBlockEnd
                    self.payloadLength = nil
                    context.fireChannelRead(self.wrapInboundOut(context.channel.allocator.buffer(capacity: 0)))
                    return .continue
                }
                // cool, let's just shift to the `.waitingForPayload` state and continue.
                self.state = .waitingForPayload(length: payloadLength)
                self.payloadLength = nil
                return .continue
            } else {
                // this happens if we reached the end of the header block but we haven't seen the Content-Length
                // header, that's an error. It will be sent through the `Channel` and decoder won't be called
                // again.
                throw DecodingError.missingContentLengthHeader
            }
        }

        // `decode` will be invoked whenever there is more data available (or if we return `.continue`).
        public mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
            switch self.state {
            case .waitingForHeaderNameOrHeaderBlockEnd:
                // Given that we're waiting for the end of a header block or a new header field, it's sensible to
                // check if this might be the end of the block.
                if buffer.readableBytesView.starts(with: "\r\n".utf8) {
                    buffer.moveReaderIndex(forwardBy: 2) // skip \r\n\r\n
                    return try self.processHeaderBlockEnd(context: context)
                }

                // Given that this is not the end of a header block, it must be a new header field. A new header field
                // must always have a colon (or we don't have enough data).
                if let colonIndex = buffer.readableBytesView.firstIndex(of: UInt8(ascii: ":")) {
                    let headerName = buffer.readString(length: colonIndex - buffer.readableBytesView.startIndex)!
                    buffer.moveReaderIndex(forwardBy: 1) // skip the colon
                    self.state = .waitingForHeaderValue(name: headerName.trimmed().lowercased())
                    return .continue
                }

                return .needMoreData
            case .waitingForHeaderValue(name: let headerName):
                // Cool, we're waiting for a header value (ie. we're after the colon).

                // Let's not bother unless we found the whole thing
                guard let newlineIndex = buffer.readableBytesView.firstIndex(of: UInt8(ascii: "\n")) else {
                    return .needMoreData
                }

                // Is this a header we actually care about?
                if headerName == "content-length" {
                    // Yes, let's parse the int.
                    let headerValue = buffer.readString(length: newlineIndex - buffer.readableBytesView.startIndex + 1)!
                    if let length = UInt32(headerValue.trimmed()) { // anything more than 4GB or negative doesn't make sense
                        self.payloadLength = .init(length)
                    } else {
                        throw DecodingError.illegalContentLengthHeaderValue(headerValue)
                    }
                } else {
                    // Nope, let's just skip over it
                    buffer.moveReaderIndex(forwardBy: newlineIndex - buffer.readableBytesView.startIndex + 1)
                }

                // but in any case, we're now waiting for a new header or the end of the header block again.
                self.state = .waitingForHeaderNameOrHeaderBlockEnd
                return .continue
            case .waitingForPayload(length: let length):
                // That's the easiest case, let's just wait until we have enough data.
                if let payload = buffer.readSlice(length: length) {
                    // Cool, we got enough data, let's go back waiting for a new header block.
                    self.state = .waitingForHeaderNameOrHeaderBlockEnd
                    // And send what we found through the pipeline.
                    context.fireChannelRead(self.wrapInboundOut(payload))
                    return .continue
                } else {
                    return .needMoreData
                }
            }
        }

        /// Invoked when the `Channel` is being brough down.
        public mutating func decodeLast(context: ChannelHandlerContext,
                                        buffer: inout ByteBuffer,
                                        seenEOF: Bool) throws -> DecodingState {
            // Last chance to decode anything.
            while try self.decode(context: context, buffer: &buffer) == .continue {}

            if buffer.readableBytes > 0 {
                // Oops, there are leftovers that don't form a full message, we could ignore those but it doesn't hurt to send
                // an error.
                throw ByteToMessageDecoderError.leftoverDataWhenDone(buffer)
            }
            return .needMoreData
        }
    }
}

extension String {
    func trimmed() -> Substring {
        guard let firstElementIndex = self.firstIndex(where: { !$0.isWhitespace }) else {
            return Substring("")
        }

        let lastElementIndex = self.reversed().firstIndex(where: { !$0.isWhitespace })!
        return self[firstElementIndex ..< lastElementIndex.base]
    }
}
