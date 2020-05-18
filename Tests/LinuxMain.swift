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
//
// LinuxMain.swift
//
import XCTest

///
/// NOTE: This file was generated by generate_linux_tests.rb
///
/// Do NOT edit this file directly as it will be regenerated automatically when needed.
///

#if os(Linux) || os(FreeBSD)
   @testable import NIOExtrasTests
   @testable import NIOHTTPCompressionTests

   XCTMain([
         testCase(DebugInboundEventsHandlerTest.allTests),
         testCase(DebugOutboundEventsHandlerTest.allTests),
         testCase(FixedLengthFrameDecoderTest.allTests),
         testCase(HTTPRequestCompressorTest.allTests),
         testCase(HTTPRequestDecompressorTest.allTests),
         testCase(HTTPResponseCompressorTest.allTests),
         testCase(HTTPResponseDecompressorTest.allTests),
         testCase(JSONRPCFramingContentLengthHeaderDecoderTests.allTests),
         testCase(JSONRPCFramingContentLengthHeaderEncoderTests.allTests),
         testCase(LengthFieldBasedFrameDecoderTest.allTests),
         testCase(LengthFieldPrependerTest.allTests),
         testCase(LineBasedFrameDecoderTest.allTests),
         testCase(QuiescingHelperTest.allTests),
         testCase(RequestResponseHandlerTest.allTests),
         testCase(WritePCAPHandlerTest.allTests),
    ])
#endif
