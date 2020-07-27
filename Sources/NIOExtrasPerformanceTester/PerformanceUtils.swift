//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch
import NIO
import NIOHTTP1

public func measure(_ fn: () throws -> Int) rethrows -> [Double] {
    func measureOne(_ fn: () throws -> Int) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        _ = try fn()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / Double(TimeAmount.seconds(1).nanoseconds)
    }

    _ = try measureOne(fn) /* pre-heat and throw away */
    var measurements = Array(repeating: 0.0, count: 10)
    for i in 0..<10 {
        measurements[i] = try measureOne(fn)
    }

    return measurements
}

public func measureAndPrint(desc: String, fn: () throws -> Int) rethrows -> Void {
    print("measuring\(warning): \(desc): ", terminator: "")
    let measurements = try measure(fn)
    print(measurements.reduce(into: "") { $0.append("\($1), ") })
}

// MARK: Utilities

final class SimpleHTTPServer: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var files: [String] = Array()
    private var seenEnd: Bool = false
    private var sentEnd: Bool = false
    private var isOpen: Bool = true

    private let cachedHead: HTTPResponseHead
    private let cachedBody: [UInt8]
    private let bodyLength = 1024
    private let numberOfAdditionalHeaders = 10

    init() {
        var head = HTTPResponseHead(version: HTTPVersion(major: 1, minor: 1), status: .ok)
        head.headers.add(name: "Content-Length", value: "\(self.bodyLength)")
        for i in 0..<self.numberOfAdditionalHeaders {
            head.headers.add(name: "X-Random-Extra-Header", value: "\(i)")
        }
        self.cachedHead = head

        var body: [UInt8] = []
        body.reserveCapacity(self.bodyLength)
        for i in 0..<self.bodyLength {
            body.append(UInt8(i % Int(UInt8.max)))
        }
        self.cachedBody = body
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case .head(let req) = self.unwrapInboundIn(data) {
            switch req.uri {
            case "/perf-test-1":
                var buffer = context.channel.allocator.buffer(capacity: self.cachedBody.count)
                buffer.writeBytes(self.cachedBody)
                context.write(self.wrapOutboundOut(.head(self.cachedHead)), promise: nil)
                context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
                return
            case "/perf-test-2":
                var req = HTTPResponseHead(version: HTTPVersion(major: 1, minor: 1), status: .ok)
                for i in 1...8 {
                    req.headers.add(name: "X-ResponseHeader-\(i)", value: "foo")
                }
                req.headers.add(name: "content-length", value: "0")
                context.write(self.wrapOutboundOut(.head(req)), promise: nil)
                context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
                return
            default:
                fatalError("unknown uri \(req.uri)")
            }
        }
    }
}

final class RepeatedRequests: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private let numberOfRequests: Int
    private var remainingNumberOfRequests: Int
    private var doneRequests = 0
    private let isDonePromise: EventLoopPromise<Int>

    init(numberOfRequests: Int, eventLoop: EventLoop) {
        self.remainingNumberOfRequests = numberOfRequests
        self.numberOfRequests = numberOfRequests
        self.isDonePromise = eventLoop.makePromise()
    }

    func wait() throws -> Int {
        let reqs = try self.isDonePromise.futureResult.wait()
        precondition(reqs == self.numberOfRequests)
        return reqs
    }

    var completedFuture: EventLoopFuture<Int> { self.isDonePromise.futureResult }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.channel.close(promise: nil)
        self.isDonePromise.fail(error)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        if case .end(nil) = reqPart {
            if self.remainingNumberOfRequests <= 0 {
                context.channel.close().map { self.doneRequests }.cascade(to: self.isDonePromise)
            } else {
                self.doneRequests += 1
                self.remainingNumberOfRequests -= 1

                context.write(self.wrapOutboundOut(.head(head)), promise: nil)
                context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }
        }
    }
}

private func someString(size: Int) -> String {
    var s = "A"
    for f in 1..<size {
        s += String("\(f)".first!)
    }
    return s
}
