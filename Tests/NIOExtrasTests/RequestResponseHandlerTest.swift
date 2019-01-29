//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import XCTest
import NIO
import NIOExtras

class RequestResponseHandlerTest: XCTestCase {
    private var eventLoop: EmbeddedEventLoop!
    private var channel: EmbeddedChannel!
    private var buffer: ByteBuffer!

    override func setUp() {
        super.setUp()

        self.eventLoop = EmbeddedEventLoop()
        self.channel = EmbeddedChannel(loop: self.eventLoop)
        self.buffer = self.channel.allocator.buffer(capacity: 16)
    }

    override func tearDown() {
        self.buffer = nil
        self.eventLoop = nil
        if self.channel.isActive {
            XCTAssertNoThrow(XCTAssertFalse(try self.channel.finish()))
        }

        super.tearDown()
    }

    func testSimpleRequestWorks() {
        XCTAssertNoThrow(try self.channel.pipeline.add(handler: RequestResponseHandler<IOData, String>()).wait())
        self.buffer.write(string: "hello")

        // pretend to connect to the EmbeddedChannel knows it's supposed to be active
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5)).wait())

        let p: EventLoopPromise<String> = self.channel.eventLoop.newPromise()
        // write request
        XCTAssertNoThrow(try self.channel.writeOutbound((IOData.byteBuffer(self.buffer), p)))
        // write response
        XCTAssertNoThrow(try self.channel.writeInbound("okay"))
        // verify request was forwarded
        XCTAssertEqual(IOData.byteBuffer(self.buffer), self.channel.readOutbound())
        // verify response was not forwarded
        XCTAssertEqual(nil, self.channel.readInbound() as IOData?)
        // verify the promise got succeeded with the response
        XCTAssertNoThrow(XCTAssertEqual("okay", try p.futureResult.wait()))
    }

    func testEnqueingMultipleRequestsWorks() {
        struct DummyError: Error {}
        XCTAssertNoThrow(try self.channel.pipeline.add(handler: RequestResponseHandler<IOData, Int>()).wait())

        var futures: [EventLoopFuture<Int>] = []
        // pretend to connect to the EmbeddedChannel knows it's supposed to be active
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5)).wait())

        for reqId in 0..<5 {
            self.buffer.clear()
            self.buffer.write(string: "\(reqId)")

            let p: EventLoopPromise<Int> = self.channel.eventLoop.newPromise()
            futures.append(p.futureResult)

            // write request
            XCTAssertNoThrow(try self.channel.writeOutbound((IOData.byteBuffer(self.buffer), p)))
        }

        // let's have 3 successful responses
        for reqIdExpected in 0..<3 {
            switch self.channel.readOutbound() {
            case .some(.byteBuffer(var buffer)):
                if let reqId = buffer.readString(length: buffer.readableBytes).flatMap(Int.init) {
                    // write response
                    XCTAssertNoThrow(try self.channel.writeInbound(reqId))
                } else {
                    XCTFail("couldn't get request id")
                }
            default:
                XCTFail("could not find request")
            }
            XCTAssertNoThrow(XCTAssertEqual(reqIdExpected, try futures[reqIdExpected].wait()))
        }

        // validate the Channel is active
        XCTAssertTrue(self.channel.isActive)
        self.channel.pipeline.fireErrorCaught(DummyError())

        // after receiving an error, it should be closed
        XCTAssertFalse(self.channel.isActive)

        for failedReqId in 3..<5 {
            XCTAssertThrowsError(try futures[failedReqId].wait()) { error in
                XCTAssertNotNil(error as? DummyError)
            }
        }

        // verify no response was not forwarded
        XCTAssertEqual(nil, self.channel.readInbound() as IOData?)
    }

    func testRequestsEnqueuedAfterErrorAreFailed() {
        struct DummyError: Error {}
        XCTAssertNoThrow(try self.channel.pipeline.add(handler: RequestResponseHandler<IOData, Void>()).wait())

        self.channel.pipeline.fireErrorCaught(DummyError())

        let p: EventLoopPromise<Void> = self.eventLoop.newPromise()
        XCTAssertThrowsError(try self.channel.writeOutbound((IOData.byteBuffer(self.buffer), p))) { error in
            XCTAssertNotNil(error as? DummyError)
        }
        XCTAssertThrowsError(try p.futureResult.wait()) { error in
            XCTAssertNotNil(error as? DummyError)
        }
    }

    func testRequestsEnqueuedJustBeforeErrorAreFailed() {
        struct DummyError1: Error {}
        struct DummyError2: Error {}

        XCTAssertNoThrow(try self.channel.pipeline.add(handler: RequestResponseHandler<IOData, Void>()).wait())

        let p: EventLoopPromise<Void> = self.eventLoop.newPromise()
        // right now, everything's still okay so the enqueued request won't immediately be failed
        XCTAssertNoThrow(try self.channel.writeOutbound((IOData.byteBuffer(self.buffer), p)))

        // but whilst we're waiting for the response, an error turns up
        self.channel.pipeline.fireErrorCaught(DummyError1())

        // we'll also fire a second error through the pipeline that shouldn't do anything
        self.channel.pipeline.fireErrorCaught(DummyError2())


        // and just after the error, the response arrives too (but too late)
        XCTAssertNoThrow(try self.channel.writeInbound(()))

        XCTAssertThrowsError(try p.futureResult.wait()) { error in
            XCTAssertNotNil(error as? DummyError1)
        }
    }
}
