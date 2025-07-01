//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2025 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOEmbedded
import NIOExtras
import XCTest

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
            XCTAssertNoThrow(XCTAssertTrue(try self.channel.finish().isClean))
        }

        super.tearDown()
    }

    func testSimpleRequestWorks() {
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(RequestResponseHandler<IOData, String>()))
        self.buffer.writeString("hello")

        // pretend to connect to the EmbeddedChannel knows it's supposed to be active
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5)).wait())

        let p: EventLoopPromise<String> = self.channel.eventLoop.makePromise()
        // write request
        XCTAssertNoThrow(try self.channel.writeOutbound((IOData.byteBuffer(self.buffer), p)))
        // write response
        XCTAssertNoThrow(try self.channel.writeInbound("okay"))
        // verify request was forwarded
        XCTAssertNoThrow(XCTAssertEqual(IOData.byteBuffer(self.buffer), try self.channel.readOutbound()))
        // verify response was not forwarded
        XCTAssertNoThrow(XCTAssertEqual(nil, try self.channel.readInbound(as: IOData.self)))
        // verify the promise got succeeded with the response
        XCTAssertNoThrow(XCTAssertEqual("okay", try p.futureResult.wait()))
    }

    func testReadOnEmptyBuffer() {
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(RequestResponseHandler<IOData, String>()))

        // pretend to connect to the EmbeddedChannel knows it's supposed to be active
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5)).wait())

        // read from the empty handler
        XCTAssertThrowsError(try self.channel.writeInbound("should error")) { error in
            XCTAssertTrue(error is NIOExtrasErrors.ResponsePromiseBufferEmpty)
        }
    }

    func testEnqueingMultipleRequestsWorks() throws {
        struct DummyError: Error {}
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(RequestResponseHandler<IOData, Int>()))

        var futures: [EventLoopFuture<Int>] = []
        // pretend to connect to the EmbeddedChannel knows it's supposed to be active
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5)).wait())

        for reqId in 0..<5 {
            self.buffer.clear()
            self.buffer.writeString("\(reqId)")

            let p: EventLoopPromise<Int> = self.channel.eventLoop.makePromise()
            futures.append(p.futureResult)

            // write request
            XCTAssertNoThrow(try self.channel.writeOutbound((IOData.byteBuffer(self.buffer), p)))
        }

        // let's have 3 successful responses
        for reqIdExpected in 0..<3 {
            switch try self.channel.readOutbound(as: IOData.self) {
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
        XCTAssertNoThrow(XCTAssertEqual(nil, try self.channel.readInbound(as: IOData.self)))
    }

    func testRequestsEnqueuedAfterErrorAreFailed() {
        struct DummyError: Error {}
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(RequestResponseHandler<IOData, Void>()))

        self.channel.pipeline.fireErrorCaught(DummyError())

        let p: EventLoopPromise<Void> = self.eventLoop.makePromise()
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

        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(RequestResponseHandler<IOData, Void>()))

        let p: EventLoopPromise<Void> = self.eventLoop.makePromise()
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

    func testClosedConnectionFailsOutstandingPromises() {
        XCTAssertNoThrow(try self.channel.pipeline.syncOperations.addHandler(RequestResponseHandler<String, Void>()))

        let promise = self.eventLoop.makePromise(of: Void.self)
        XCTAssertNoThrow(try self.channel.writeOutbound(("Hello!", promise)))

        XCTAssertNoThrow(try self.channel.close().wait())
        XCTAssertThrowsError(try promise.futureResult.wait()) { error in
            XCTAssertTrue(error is NIOExtrasErrors.ClosedBeforeReceivingResponse)
        }
    }
}

class NIORequestIsolatedResponseHandlerTest: XCTestCase {
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
            XCTAssertNoThrow(XCTAssertTrue(try self.channel.finish().isClean))
        }

        super.tearDown()
    }

    func testSimpleRequestWorks() {
        XCTAssertNoThrow(
            try self.channel.pipeline.syncOperations.addHandler(NIORequestIsolatedResponseHandler<IOData, NSString>())
        )
        self.buffer.writeString("hello")

        // pretend to connect to the EmbeddedChannel knows it's supposed to be active
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5)).wait())

        let p: EventLoopPromise<NSString>.Isolated = self.channel.eventLoop.makePromise().assumeIsolated()
        // write request
        XCTAssertNoThrow(try self.channel.writeOutbound((IOData.byteBuffer(self.buffer), p)))
        // write response
        XCTAssertNoThrow(try self.channel.writeInbound("okay"))
        // verify request was forwarded
        XCTAssertNoThrow(XCTAssertEqual(IOData.byteBuffer(self.buffer), try self.channel.readOutbound()))
        // verify response was not forwarded
        XCTAssertNoThrow(XCTAssertEqual(nil, try self.channel.readInbound(as: IOData.self)))
        // verify the promise got succeeded with the response
        p.futureResult.whenComplete { res in
            switch res {
            case .success(let value):
                XCTAssertEqual("okay", value)
            case .failure(_):
                XCTFail()
            }
        }
    }

    func testReadOnEmptyBuffer() {
        XCTAssertNoThrow(
            try self.channel.pipeline.syncOperations.addHandler(NIORequestIsolatedResponseHandler<IOData, NSString>())
        )

        // pretend to connect to the EmbeddedChannel knows it's supposed to be active
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5)).wait())

        // read from the empty handler
        XCTAssertThrowsError(try self.channel.writeInbound("should error")) { error in
            XCTAssertTrue(error is NIOExtrasErrors.ResponsePromiseBufferEmpty)
        }
    }

    func testEnqueingMultipleRequestsWorks() throws {
        struct DummyError: Error {}
        XCTAssertNoThrow(
            try self.channel.pipeline.syncOperations.addHandler(NIORequestIsolatedResponseHandler<IOData, NSString>())
        )

        var futures: [EventLoopFuture<NSString>.Isolated] = []
        // pretend to connect to the EmbeddedChannel knows it's supposed to be active
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5)).wait())

        for reqId in 0..<5 {
            self.buffer.clear()
            self.buffer.writeString("\(reqId)")

            let p: EventLoopPromise<NSString>.Isolated = self.channel.eventLoop.makePromise().assumeIsolated()
            futures.append(p.futureResult)

            // write request
            XCTAssertNoThrow(try self.channel.writeOutbound((IOData.byteBuffer(self.buffer), p)))
        }

        // let's have 3 successful responses
        for reqIdExpected in 0..<3 {
            switch try self.channel.readOutbound(as: IOData.self) {
            case .some(.byteBuffer(var buffer)):
                if let reqId = buffer.readString(length: buffer.readableBytes) {
                    // write response
                    XCTAssertNoThrow(try self.channel.writeInbound(reqId))
                } else {
                    XCTFail("couldn't get request id")
                }
            default:
                XCTFail("could not find request")
            }
            futures[reqIdExpected].whenComplete { res in
                switch res {
                case .success(let value):
                    XCTAssertEqual(reqIdExpected, value.integerValue)
                case .failure(_):
                    XCTFail()
                }
            }
        }

        // validate the Channel is active
        XCTAssertTrue(self.channel.isActive)
        self.channel.pipeline.fireErrorCaught(DummyError())

        // after receiving an error, it should be closed
        XCTAssertFalse(self.channel.isActive)

        for failedReqId in 3..<5 {
            futures[failedReqId].whenComplete { res in
                switch res {
                case .success(_):
                    XCTFail()
                case .failure(let error):
                    XCTAssertNotNil(error as? DummyError)
                }
            }
        }

        // verify no response was not forwarded
        XCTAssertNoThrow(XCTAssertEqual(nil, try self.channel.readInbound(as: IOData.self)))
    }

    func testRequestsEnqueuedAfterErrorAreFailed() {
        struct DummyError: Error {}
        XCTAssertNoThrow(
            try self.channel.pipeline.syncOperations.addHandler(NIORequestIsolatedResponseHandler<IOData, Void>())
        )

        self.channel.pipeline.fireErrorCaught(DummyError())

        let p: EventLoopPromise<Void>.Isolated = self.eventLoop.makePromise().assumeIsolated()
        XCTAssertThrowsError(try self.channel.writeOutbound((IOData.byteBuffer(self.buffer), p))) { error in
            XCTAssertNotNil(error as? DummyError)
        }
        p.futureResult.whenComplete { res in
            switch res {
            case .success(_):
                XCTFail()
            case .failure(let error):
                XCTAssertNotNil(error as? DummyError)
            }
        }
    }

    func testRequestsEnqueuedJustBeforeErrorAreFailed() {
        struct DummyError1: Error {}
        struct DummyError2: Error {}

        XCTAssertNoThrow(
            try self.channel.pipeline.syncOperations.addHandler(NIORequestIsolatedResponseHandler<IOData, Void>())
        )

        let p: EventLoopPromise<Void>.Isolated = self.eventLoop.makePromise().assumeIsolated()
        // right now, everything's still okay so the enqueued request won't immediately be failed
        XCTAssertNoThrow(try self.channel.writeOutbound((IOData.byteBuffer(self.buffer), p)))

        // but whilst we're waiting for the response, an error turns up
        self.channel.pipeline.fireErrorCaught(DummyError1())

        // we'll also fire a second error through the pipeline that shouldn't do anything
        self.channel.pipeline.fireErrorCaught(DummyError2())

        // and just after the error, the response arrives too (but too late)
        XCTAssertNoThrow(try self.channel.writeInbound(()))

        p.futureResult.whenComplete { res in
            switch res {
            case .success(_):
                XCTFail()
            case .failure(let error):
                XCTAssertNotNil(error as? DummyError1)
            }
        }
    }

    func testClosedConnectionFailsOutstandingPromises() {
        XCTAssertNoThrow(
            try self.channel.pipeline.syncOperations.addHandler(NIORequestIsolatedResponseHandler<String, Void>())
        )

        let promise = self.eventLoop.makePromise(of: Void.self).assumeIsolated()
        XCTAssertNoThrow(try self.channel.writeOutbound(("Hello!", promise)))

        XCTAssertNoThrow(try self.channel.close().wait())

        promise.futureResult.whenComplete { result in
            switch result {
            case .success(_):
                XCTFail()
            case .failure(let error):
                XCTAssertTrue(error is NIOExtrasErrors.ClosedBeforeReceivingResponse)
            }
        }
    }
}
