// swift-tools-version:5.2
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
    .target(
        name: "NIOExtras",
        dependencies: [
            .product(name: "NIO", package: "swift-nio")
        ]),
    .target(
        name: "NIOHTTPCompression",
        dependencies: [
            "CNIOExtrasZlib",
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]),
    .target(
        name: "HTTPServerWithQuiescingDemo",
        dependencies: [
            "NIOExtras",
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]),
    .target(
        name: "NIOWritePCAPDemo",
        dependencies: [
            "NIOExtras",
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]),
    .target(
        name: "NIOWritePartialPCAPDemo",
        dependencies: [
            "NIOExtras",
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]),
    .target(
        name: "NIOExtrasPerformanceTester",
        dependencies: [
            "NIOExtras",
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]),
    .target(
        name: "NIOSOCKS",
        dependencies: [
            .product(name: "NIO", package: "swift-nio")
        ]),
    .target(
        name: "NIOSOCKSClient",
        dependencies: [
            .product(name: "NIO", package: "swift-nio"),
            "NIOSOCKS"
        ]),
    .target(
        name: "CNIOExtrasZlib",
        dependencies: [],
        linkerSettings: [
            .linkedLibrary("z")
        ]),
    .testTarget(
        name: "NIOExtrasTests",
        dependencies: [
            "NIOExtras",
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOTestUtils", package: "swift-nio"),
            .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
        ]),
    .testTarget(
        name: "NIOHTTPCompressionTests",
        dependencies: [
            "NIOHTTPCompression"
        ]),
    .testTarget(
        name: "NIOSOCKSTests",
        dependencies: [
            "NIOSOCKS",
            .product(name: "NIO", package: "swift-nio"),
        ])
]

let package = Package(
    name: "swift-nio-extras",
    products: [
        .library(name: "NIOExtras", targets: ["NIOExtras"]),
        .library(name: "NIOSOCKS", targets: ["NIOSOCKS"]),
        .library(name: "NIOHTTPCompression", targets: ["NIOHTTPCompression"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.29.0"),
    ],
    targets: targets
)
