//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2023 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import XCTest
import NIOCore
import NIOEmbedded
import NIOExtras

class RequestResponseWithIDHandlerTest: XCTestCase {
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
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(NIORequestResponseWithIDHandler<ValueWithRequestID<IOData>, ValueWithRequestID<String>>()).wait())
        self.buffer.writeString("hello")

        // pretend to connect to the EmbeddedChannel knows it's supposed to be active
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5)).wait())

        let p: EventLoopPromise<ValueWithRequestID<String>> = self.channel.eventLoop.makePromise()
        // write request
        XCTAssertNoThrow(try self.channel.writeOutbound((ValueWithRequestID(requestID: 1, value: IOData.byteBuffer(self.buffer)),
                                                         p)))
        // write response
        XCTAssertNoThrow(try self.channel.writeInbound(ValueWithRequestID(requestID: 1, value: "okay")))
        // verify request was forwarded
        XCTAssertEqual(ValueWithRequestID(requestID: 1, value: IOData.byteBuffer(self.buffer)),
                                        try self.channel.readOutbound())
        // verify response was not forwarded
        XCTAssertEqual(nil, try self.channel.readInbound(as: ValueWithRequestID<IOData>.self))
        // verify the promise got succeeded with the response
        XCTAssertEqual(ValueWithRequestID(requestID: 1, value: "okay"), try p.futureResult.wait())
    }

    func testEnqueingMultipleRequestsWorks() throws {
        struct DummyError: Error {}
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(NIORequestResponseWithIDHandler<ValueWithRequestID<IOData>, ValueWithRequestID<Int>>()).wait())

        var futures: [EventLoopFuture<ValueWithRequestID<Int>>] = []
        // pretend to connect to the EmbeddedChannel knows it's supposed to be active
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5)).wait())

        for reqId in 0..<5 {
            self.buffer.clear()
            self.buffer.writeString("\(reqId)")

            let p: EventLoopPromise<ValueWithRequestID<Int>> = self.channel.eventLoop.makePromise()
            futures.append(p.futureResult)

            // write request
            XCTAssertNoThrow(try self.channel.writeOutbound((ValueWithRequestID(requestID: reqId,
                                                                    value: IOData.byteBuffer(self.buffer)), p)))
        }

        // let's have 3 successful responses
        for reqIdExpected in 0..<3 {
            switch try self.channel.readOutbound(as: ValueWithRequestID<IOData>.self) {
            case .some(let req):
                guard case .byteBuffer(var buffer) = req.value else {
                    XCTFail("wrong type")
                    return
                }
                if let reqId = buffer.readString(length: buffer.readableBytes).flatMap(Int.init) {
                    // write response
                    try self.channel.writeInbound(ValueWithRequestID(requestID: reqId, value: reqId))
                } else {
                    XCTFail("couldn't get request id")
                }
            default:
                XCTFail("could not find request")
            }
            XCTAssertNoThrow(XCTAssertEqual(ValueWithRequestID(requestID: reqIdExpected, value: reqIdExpected),
                                            try futures[reqIdExpected].wait()))
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
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(NIORequestResponseWithIDHandler<ValueWithRequestID<IOData>, ValueWithRequestID<Void>>()).wait())

        self.channel.pipeline.fireErrorCaught(DummyError())

        let p: EventLoopPromise<ValueWithRequestID<Void>> = self.eventLoop.makePromise()
        XCTAssertThrowsError(try self.channel.writeOutbound((ValueWithRequestID(requestID: 1,
                                                                    value: IOData.byteBuffer(self.buffer)), p))) { error in
            XCTAssertNotNil(error as? DummyError)
        }
        XCTAssertThrowsError(try p.futureResult.wait()) { error in
            XCTAssertNotNil(error as? DummyError)
        }
    }

    func testRequestsEnqueuedJustBeforeErrorAreFailed() {
        struct DummyError1: Error {}
        struct DummyError2: Error {}

        XCTAssertNoThrow(try self.channel.pipeline.addHandler(NIORequestResponseWithIDHandler<ValueWithRequestID<IOData>, ValueWithRequestID<Void>>()).wait())

        let p: EventLoopPromise<ValueWithRequestID<Void>> = self.eventLoop.makePromise()
        // right now, everything's still okay so the enqueued request won't immediately be failed
        XCTAssertNoThrow(try self.channel.writeOutbound((ValueWithRequestID(requestID: 1, value: IOData.byteBuffer(self.buffer)),
                                                         p)))

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
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(NIORequestResponseWithIDHandler<ValueWithRequestID<String>, ValueWithRequestID<Void>>()).wait())

        let promise = self.eventLoop.makePromise(of: ValueWithRequestID<Void>.self)
        XCTAssertNoThrow(try self.channel.writeOutbound((ValueWithRequestID(requestID: 1, value: "Hello!"), promise)))

        XCTAssertNoThrow(try self.channel.close().wait())
        XCTAssertThrowsError(try promise.futureResult.wait()) { error in
            XCTAssertTrue(error is NIOExtrasErrors.ClosedBeforeReceivingResponse)
        }
    }

    func testOutOfOrderResponsesWork() {
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(NIORequestResponseWithIDHandler<ValueWithRequestID<String>, ValueWithRequestID<String>>()).wait())
        self.buffer.writeString("hello")

        // pretend to connect to the EmbeddedChannel knows it's supposed to be active
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5)).wait())

        let p1: EventLoopPromise<ValueWithRequestID<String>> = self.channel.eventLoop.makePromise()
        let p2: EventLoopPromise<ValueWithRequestID<String>> = self.channel.eventLoop.makePromise()

        // write requests
        XCTAssertNoThrow(try self.channel.writeOutbound((ValueWithRequestID(requestID: 1, value: "1"), p1)))
        XCTAssertNoThrow(try self.channel.writeOutbound((ValueWithRequestID(requestID: 2, value: "2"), p2)))
        // write responses but out of order
        XCTAssertNoThrow(try self.channel.writeInbound(ValueWithRequestID(requestID: 2, value: "okay 2")))
        XCTAssertNoThrow(try self.channel.writeInbound(ValueWithRequestID(requestID: 1, value: "okay 1")))
        // verify requests was forwarded
        XCTAssertEqual(ValueWithRequestID(requestID: 1, value: "1"), try self.channel.readOutbound())
        XCTAssertEqual(ValueWithRequestID(requestID: 2, value: "2"), try self.channel.readOutbound())
        // verify responses were not forwarded
        XCTAssertEqual(nil, try self.channel.readInbound(as: ValueWithRequestID<IOData>.self))
        // verify the promises got succeeded with the response
        XCTAssertEqual(ValueWithRequestID(requestID: 1, value: "okay 1"), try p1.futureResult.wait())
        XCTAssertEqual(ValueWithRequestID(requestID: 2, value: "okay 2"), try p2.futureResult.wait())
    }

    func testErrorOnResponseForNonExistantRequest() {
        XCTAssertNoThrow(try self.channel.pipeline.addHandler(NIORequestResponseWithIDHandler<ValueWithRequestID<String>, ValueWithRequestID<String>>()).wait())
        self.buffer.writeString("hello")

        // pretend to connect to the EmbeddedChannel knows it's supposed to be active
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5)).wait())

        let p1: EventLoopPromise<ValueWithRequestID<String>> = self.channel.eventLoop.makePromise()

        // write request
        XCTAssertNoThrow(try self.channel.writeOutbound((ValueWithRequestID(requestID: 1, value: "1"), p1)))
        // write wrong response
        XCTAssertThrowsError(try self.channel.writeInbound(ValueWithRequestID(requestID: 2, value: "okay 2"))) { error in
            guard let error = error as? NIOExtrasErrors.ResponseForInvalidRequest<ValueWithRequestID<String>> else {
                XCTFail("wrong error")
                return
            }
            XCTAssertEqual(2, error.requestID)

        }
        // verify requests was forwarded
        XCTAssertEqual(ValueWithRequestID(requestID: 1, value: "1"), try self.channel.readOutbound())
        // verify responses were not forwarded
        XCTAssertEqual(nil, try self.channel.readInbound(as: ValueWithRequestID<IOData>.self))
        // verify the promises got succeeded with the response
    }

    func testMoreRequestsAfterChannelInactiveFail() {
        final class EmitRequestOnInactiveHandler: ChannelDuplexHandler {
            typealias InboundIn = Never
            typealias OutboundIn = (ValueWithRequestID<IOData>, EventLoopPromise<ValueWithRequestID<String>>)
            typealias OutboundOut = (ValueWithRequestID<IOData>, EventLoopPromise<ValueWithRequestID<String>>)

            func channelInactive(context: ChannelHandlerContext) {
                let responsePromise = context.eventLoop.makePromise(of: ValueWithRequestID<String>.self)
                let writePromise = context.eventLoop.makePromise(of: Void.self)
                context.writeAndFlush(self.wrapOutboundOut(
                    (ValueWithRequestID(requestID: 1, value: IOData.byteBuffer(ByteBuffer(string: "hi"))), responsePromise)
                    ),
                                      promise: writePromise)
                var writePromiseCompleted = false
                defer {
                    XCTAssertTrue(writePromiseCompleted)
                }
                var responsePromiseCompleted = false
                defer {
                    XCTAssertTrue(responsePromiseCompleted)
                }
                writePromise.futureResult.whenComplete { result in
                    writePromiseCompleted = true
                    switch result {
                    case .success:
                        XCTFail("shouldn't succeed")
                    case .failure(let error):
                        XCTAssertEqual(.ioOnClosedChannel, error as? ChannelError)
                    }
                }
                responsePromise.futureResult.whenComplete { result in
                    responsePromiseCompleted = true
                    switch result {
                    case .success:
                        XCTFail("shouldn't succeed")
                    case .failure(let error):
                        XCTAssertEqual(.ioOnClosedChannel, error as? ChannelError)
                    }
                }
            }
        }

        XCTAssertNoThrow(try self.channel.pipeline.addHandlers(
            NIORequestResponseWithIDHandler<ValueWithRequestID<IOData>, ValueWithRequestID<String>>(),
            EmitRequestOnInactiveHandler()
        ).wait())
        self.buffer.writeString("hello")

        // pretend to connect to the EmbeddedChannel knows it's supposed to be active
        XCTAssertNoThrow(try self.channel.connect(to: .init(ipAddress: "1.2.3.4", port: 5)).wait())

        let p: EventLoopPromise<ValueWithRequestID<String>> = self.channel.eventLoop.makePromise()
        // write request
        XCTAssertNoThrow(try self.channel.writeOutbound((ValueWithRequestID(requestID: 1, value: IOData.byteBuffer(self.buffer)),
                                                         p)))
        // write response
        XCTAssertNoThrow(try self.channel.writeInbound(ValueWithRequestID(requestID: 1, value: "okay")))

        // verify request was forwarded
        XCTAssertEqual(ValueWithRequestID(requestID: 1, value: IOData.byteBuffer(self.buffer)),
                                        try self.channel.readOutbound())

        // verify the promise got succeeded with the response
        XCTAssertEqual(ValueWithRequestID(requestID: 1, value: "okay"), try p.futureResult.wait())
    }
}

struct ValueWithRequestID<T>: NIORequestIdentifiable {
    typealias RequestID = Int

    var requestID: Int
    var value: T
}

extension ValueWithRequestID: Equatable where T: Equatable {
}
