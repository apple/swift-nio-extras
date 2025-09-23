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

class DebugOutboundEventsHandlerTest: XCTestCase {

    private var channel: EmbeddedChannel!
    private var lastEvent: DebugOutboundEventsHandler.Event!
    private var handlerUnderTest: DebugOutboundEventsHandler!

    override func setUp() {
        super.setUp()
        channel = EmbeddedChannel()
        handlerUnderTest = DebugOutboundEventsHandler { event, _ in
            self.lastEvent = event
        }
        try? channel.pipeline.syncOperations.addHandler(handlerUnderTest)
    }

    override func tearDown() {
        channel = nil
        lastEvent = nil
        handlerUnderTest = nil
        super.tearDown()
    }

    func testRegister() {
        channel.pipeline.register(promise: nil)
        XCTAssertEqual(lastEvent, .register)
    }

    func testBind() throws {
        let address = try SocketAddress(unixDomainSocketPath: "path")
        channel.bind(to: address, promise: nil)
        XCTAssertEqual(lastEvent, .bind(address: address))
    }

    func testConnect() throws {
        let address = try SocketAddress(unixDomainSocketPath: "path")
        channel.connect(to: address, promise: nil)
        XCTAssertEqual(lastEvent, .connect(address: address))
    }

    func testWrite() {
        let data = " 1 2 3 "
        channel.write(" 1 2 3 ", promise: nil)
        XCTAssertEqual(lastEvent, .write(data: NIOAny(data)))
    }

    func testFlush() {
        channel.flush()
        XCTAssertEqual(lastEvent, .flush)
    }

    func testRead() {
        channel.read()
        XCTAssertEqual(lastEvent, .read)
    }

    func testClose() {
        channel.close(mode: .all, promise: nil)
        XCTAssertEqual(lastEvent, .close(mode: .all))
    }

    func testTriggerUserOutboundEvent() {
        let event = "user event"
        channel.triggerUserOutboundEvent(event, promise: nil)
        XCTAssertEqual(lastEvent, .triggerUserOutboundEvent(event: event))
    }

}

extension DebugOutboundEventsHandler.Event {
    public static func == (lhs: DebugOutboundEventsHandler.Event, rhs: DebugOutboundEventsHandler.Event) -> Bool {
        switch (lhs, rhs) {
        case (.register, .register):
            return true
        case (.bind(let address1), .bind(let address2)):
            return address1 == address2
        case (.connect(let address1), .connect(let address2)):
            return address1 == address2
        case (.write(let data1), .write(let data2)):
            return "\(data1)" == "\(data2)"
        case (.flush, .flush):
            return true
        case (.read, .read):
            return true
        case (.close(let mode1), .close(let mode2)):
            return mode1 == mode2
        case (.triggerUserOutboundEvent(let event1), .triggerUserOutboundEvent(let event2)):
            return "\(event1)" == "\(event2)"
        default:
            return false
        }
    }
}

extension DebugOutboundEventsHandler.Event: Equatable {}
