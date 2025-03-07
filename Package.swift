// swift-tools-version:5.8
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2024 Apple Inc. and the SwiftNIO project authors
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
    .target(
        name: "NIOResumableUpload",
        dependencies: [
            "NIOHTTPTypes",
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "StructuredFieldValues", package: "swift-http-structured-headers"),
            .product(name: "Atomics", package: "swift-atomics"),
        ]
    ),
    .executableTarget(
        name: "NIOResumableUploadDemo",
        dependencies: [
            "NIOResumableUpload",
            "NIOHTTPTypesHTTP1",
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
        ]
    ),
    .testTarget(
        name: "NIOResumableUploadTests",
        dependencies: [
            "NIOResumableUpload",
            .product(name: "NIOEmbedded", package: "swift-nio"),
        ]
    ),
    .target(
        name: "NIOHTTPResponsiveness",
        dependencies: [
            "NIOHTTPTypes",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "Algorithms", package: "swift-algorithms"),
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    ),
    .testTarget(
        name: "NIOHTTPResponsivenessTests",
        dependencies: [
            "NIOHTTPResponsiveness",
            "NIOHTTPTypes",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOEmbedded", package: "swift-nio"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
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
        .library(name: "NIOResumableUpload", targets: ["NIOResumableUpload"]),
        .library(name: "NIOHTTPResponsiveness", targets: ["NIOHTTPResponsiveness"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.77.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.27.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-http-structured-headers.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.0"),

    ],
    targets: targets
)

// ---    STANDARD CROSS-REPO SETTINGS DO NOT EDIT   --- //
for target in package.targets {
    switch target.type {
    case .regular, .test, .executable:
        var settings = target.swiftSettings ?? []
        // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md
        settings.append(.enableUpcomingFeature("MemberImportVisibility"))
        target.swiftSettings = settings
    case .macro, .plugin, .system, .binary:
        ()  // not applicable
    @unknown default:
        ()  // we don't know what to do here, do nothing
    }
}
// --- END: STANDARD CROSS-REPO SETTINGS DO NOT EDIT --- //
