// swift-tools-version:4.1
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

import PackageDescription

var targets: [PackageDescription.Target] = [
    .target(name: "NIOExtras", dependencies: ["NIO"]),
    .target(name: "HTTPServerWithQuiescingDemo", dependencies: ["NIOExtras", "NIOHTTP1"]),
    .testTarget(name: "NIOExtrasTests", dependencies: ["NIOExtras"]),
]

let package = Package(
    name: "swift-nio-extras",
    products: [
        .executable(name: "HTTPServerWithQuiescingDemo", targets: ["HTTPServerWithQuiescingDemo"]),
        .library(name: "NIOExtras", targets: ["NIOExtras"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "1.7.0"),
    ],
    targets: targets
)
