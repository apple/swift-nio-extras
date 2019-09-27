import XCTest

import NIOExtrasTests
import NIOHTTPCompressionTests

var tests = [XCTestCaseEntry]()
tests += NIOExtrasTests.__allTests()
tests += NIOHTTPCompressionTests.__allTests()

XCTMain(tests)
