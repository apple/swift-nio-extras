// swift-tools-version:5.0
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

import PackageDescription

var targets: [PackageDescription.Target] = [
    .target(name: "NIOExtras", dependencies: ["NIO"]),
    .target(name: "NIOHTTPCompression", dependencies: ["NIO", "NIOHTTP1", "CNIOExtrasZlib"]),
    .target(name: "HTTPServerWithQuiescingDemo", dependencies: ["NIOExtras", "NIOHTTP1"]),
    .target(name: "NIOWritePCAPDemo", dependencies: ["NIO", "NIOExtras", "NIOHTTP1"]),
    .target(name: "NIOWritePartialPCAPDemo", dependencies: ["NIO", "NIOExtras", "NIOHTTP1"]),
    .target(name: "NIOExtrasPerformanceTester", dependencies: ["NIO", "NIOExtras", "NIOHTTP1"]),
    .target(name: "CNIOExtrasZlib",
            dependencies: [],
            linkerSettings: [
                .linkedLibrary("z")
            ]),
    .testTarget(name: "NIOExtrasTests", dependencies: ["NIOExtras", "NIO", "NIOTestUtils", "NIOConcurrencyHelpers"]),
    .testTarget(name: "NIOHTTPCompressionTests", dependencies: ["NIOHTTPCompression"]),
]

let package = Package(
    name: "swift-nio-extras",
    products: [
        .executable(name: "HTTPServerWithQuiescingDemo", targets: ["HTTPServerWithQuiescingDemo"]),
        .executable(name: "NIOWritePCAPDemo", targets: ["NIOWritePCAPDemo"]),
        .executable(name: "NIOWritePartialPCAPDemo", targets: ["NIOWritePartialPCAPDemo"]),
        .executable(name: "NIOExtrasPerformanceTester", targets: ["NIOExtrasPerformanceTester"]),
        .library(name: "NIOExtras", targets: ["NIOExtras"]),
        .library(name: "NIOHTTPCompression", targets: ["NIOHTTPCompression"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.9.0"),
    ],
    targets: targets
)
