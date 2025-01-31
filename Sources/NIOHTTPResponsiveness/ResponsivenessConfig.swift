//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2024 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

public struct ResponsivenessConfig: Codable, Hashable, Sendable {
    public var version: Int
    public var urls: ResponsivenessConfigURLs

    public init(version: Int, urls: ResponsivenessConfigURLs) {
        self.version = version
        self.urls = urls
    }
}

public struct ResponsivenessConfigURLs: Codable, Hashable, Sendable {
    public var largeDownloadURL: String
    public var smallDownloadURL: String
    public var uploadURL: String

    enum CodingKeys: String, CodingKey {
        case largeDownloadURL = "large_download_url"
        case smallDownloadURL = "small_download_url"
        case uploadURL = "upload_url"
    }

    #if _pointerBitWidth(_32)
    static var largeDownloadSize: Int { 1_000_000_000 }  // 1 * 10^9
    #else
    static var largeDownloadSize: Int { 8_000_000_000 }  // 8 * 10^9
    #endif
    static var smallDownloadSize: Int { 1 }

    public init(scheme: String, authority: String) {
        let base = "\(scheme)://\(authority)/responsiveness"
        self.largeDownloadURL = "\(base)/download/\(ResponsivenessConfigURLs.largeDownloadSize)"
        self.smallDownloadURL = "\(base)/download/\(ResponsivenessConfigURLs.smallDownloadSize)"
        self.uploadURL = "\(base)/upload"
    }
}
