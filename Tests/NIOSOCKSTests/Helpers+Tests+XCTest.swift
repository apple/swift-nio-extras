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
// Helpers+Tests+XCTest.swift
//
import XCTest

///
/// NOTE: This file was generated by generate_linux_tests.rb
///
/// Do NOT edit this file directly as it will be regenerated automatically when needed.
///

extension HelperTests {

   static var allTests : [(String, (HelperTests) -> () throws -> Void)] {
      return [
                ("testUnwindingReturnNil", testUnwindingReturnNil),
                ("testUnwindingThrowError", testUnwindingThrowError),
                ("testUnwindingNotRequired", testUnwindingNotRequired),
           ]
   }
}

