//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2021 Apple Inc. and the SwiftNIO project authors
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

class DebugInboundEventsHandlerTest: XCTestCase {

    private var channel: EmbeddedChannel!
    private var lastEvent: DebugInboundEventsHandler.Event!
    private var handlerUnderTest: DebugInboundEventsHandler!

    override func setUp() {
        super.setUp()
        channel = EmbeddedChannel()
        handlerUnderTest = DebugInboundEventsHandler { event, _ in
            self.lastEvent = event
        }
        try? channel.pipeline.syncOperations.addHandlers(handlerUnderTest)
    }

    override func tearDown() {
        channel = nil
        lastEvent = nil
        handlerUnderTest = nil
        super.tearDown()
    }

    func testRegistered() {
        channel.pipeline.register(promise: nil)
        XCTAssertEqual(lastEvent, .registered)
    }

    func testUnregistered() {
        channel.pipeline.fireChannelUnregistered()
        XCTAssertEqual(lastEvent, .unregistered)
    }

    func testActive() {
        channel.pipeline.fireChannelActive()
        XCTAssertEqual(lastEvent, .active)
    }

    func testInactive() {
        channel.pipeline.fireChannelInactive()
        XCTAssertEqual(lastEvent, .inactive)
    }

    func testReadComplete() {
        channel.pipeline.fireChannelReadComplete()
        XCTAssertEqual(lastEvent, .readComplete)
    }

    func testWritabilityChanged() {
        channel.pipeline.fireChannelWritabilityChanged()
        XCTAssertEqual(lastEvent, .writabilityChanged(isWritable: true))
    }

    func testUserInboundEvent() {
        let eventString = "new user inbound event"
        channel.pipeline.fireUserInboundEventTriggered(eventString)
        XCTAssertEqual(lastEvent, .userInboundEventTriggered(event: eventString))
    }

    func testErrorCaught() {
        struct E: Error {
            var localizedDescription: String {
                "desc"
            }
        }
        let error = E()
        channel.pipeline.fireErrorCaught(error)
        XCTAssertEqual(lastEvent, .errorCaught(error))
    }

    func testRead() {
        let messageString = "message"
        var expectedBuffer = ByteBufferAllocator().buffer(capacity: messageString.count)
        expectedBuffer.setString(messageString, at: 0)
        channel.pipeline.fireChannelRead(expectedBuffer)
        XCTAssertEqual(lastEvent, .read(data: NIOAny(expectedBuffer)))
    }

}

extension DebugInboundEventsHandler.Event {
    public static func == (lhs: DebugInboundEventsHandler.Event, rhs: DebugInboundEventsHandler.Event) -> Bool {
        switch (lhs, rhs) {
        case (.registered, .registered):
            return true
        case (.unregistered, .unregistered):
            return true
        case (.active, .active):
            return true
        case (.inactive, .inactive):
            return true
        case (.read(let data1), .read(let data2)):
            return "\(data1)" == "\(data2)"
        case (.readComplete, .readComplete):
            return true
        case (.writabilityChanged(let isWritable1), .writabilityChanged(let isWritable2)):
            return isWritable1 == isWritable2
        case (.userInboundEventTriggered(let event1), .userInboundEventTriggered(let event2)):
            return event1 as! String == event2 as! String
        case (.errorCaught(let error1), .errorCaught(let error2)):
            return error1.localizedDescription == error2.localizedDescription
        default:
            return false
        }
    }
}

extension DebugInboundEventsHandler.Event: Equatable {}
