// swift-tools-version:5.8
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2022 Apple Inc. and the SwiftNIO project authors
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
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]
    ),
    .target(
        name: "NIOHTTPCompression",
        dependencies: [
            "CNIOExtrasZlib",
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]
    ),
    .executableTarget(
        name: "HTTPServerWithQuiescingDemo",
        dependencies: [
            "NIOExtras",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]
    ),
    .executableTarget(
        name: "NIOWritePCAPDemo",
        dependencies: [
            "NIOExtras",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]
    ),
    .executableTarget(
        name: "NIOWritePartialPCAPDemo",
        dependencies: [
            "NIOExtras",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]
    ),
    .executableTarget(
        name: "NIOExtrasPerformanceTester",
        dependencies: [
            "NIOExtras",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "NIOEmbedded", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]
    ),
    .target(
        name: "NIOSOCKS",
        dependencies: [
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "NIOCore", package: "swift-nio"),
        ]
    ),
    .executableTarget(
        name: "NIOSOCKSClient",
        dependencies: [
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
            "NIOSOCKS",
        ]
    ),
    .target(
        name: "CNIOExtrasZlib",
        dependencies: [],
        linkerSettings: [
            .linkedLibrary("z")
        ]
    ),
    .testTarget(
        name: "NIOExtrasTests",
        dependencies: [
            "NIOExtras",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOEmbedded", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "NIOTestUtils", package: "swift-nio"),
            .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
        ]
    ),
    .testTarget(
        name: "NIOHTTPCompressionTests",
        dependencies: [
            "CNIOExtrasZlib",
            "NIOHTTPCompression",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOEmbedded", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
            .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
        ]
    ),
    .testTarget(
        name: "NIOSOCKSTests",
        dependencies: [
            "NIOSOCKS",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOEmbedded", package: "swift-nio"),
        ]
    ),
    .target(
        name: "NIONFS3",
        dependencies: [
            .product(name: "NIOCore", package: "swift-nio")
        ]
    ),
    .testTarget(
        name: "NIONFS3Tests",
        dependencies: [
            "NIONFS3",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOEmbedded", package: "swift-nio"),
            .product(name: "NIOTestUtils", package: "swift-nio"),
        ]
    ),
    .target(
        name: "NIOHTTPTypes",
        dependencies: [
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "NIOCore", package: "swift-nio"),
        ]
    ),
    .target(
        name: "NIOHTTPTypesHTTP1",
        dependencies: [
            "NIOHTTPTypes",
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]
    ),
    .target(
        name: "NIOHTTPTypesHTTP2",
        dependencies: [
            "NIOHTTPTypes",
            .product(name: "NIOHTTP2", package: "swift-nio-http2"),
        ]
    ),
    .testTarget(
        name: "NIOHTTPTypesHTTP1Tests",
        dependencies: [
            "NIOHTTPTypesHTTP1"
        ]
    ),
    .testTarget(
        name: "NIOHTTPTypesHTTP2Tests",
        dependencies: [
            "NIOHTTPTypesHTTP2"
        ]
    ),
]

let package = Package(
    name: "swift-nio-extras",
    products: [
        .library(name: "NIOExtras", targets: ["NIOExtras"]),
        .library(name: "NIOSOCKS", targets: ["NIOSOCKS"]),
        .library(name: "NIOHTTPCompression", targets: ["NIOHTTPCompression"]),
        .library(name: "NIOHTTPTypes", targets: ["NIOHTTPTypes"]),
        .library(name: "NIOHTTPTypesHTTP1", targets: ["NIOHTTPTypesHTTP1"]),
        .library(name: "NIOHTTPTypesHTTP2", targets: ["NIOHTTPTypesHTTP2"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.67.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.27.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
    ],
    targets: targets
)

// ---    STANDARD CROSS-REPO SETTINGS DO NOT EDIT   --- //
for target in package.targets {
    if target.type != .plugin {
        var settings = target.swiftSettings ?? []
        // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md
        settings.append(.enableUpcomingFeature("MemberImportVisibility"))
        target.swiftSettings = settings
    }
}
// --- END: STANDARD CROSS-REPO SETTINGS DO NOT EDIT --- //
