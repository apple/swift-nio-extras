//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOConcurrencyHelpers
import NIOCore

/// `HTTPResumableUploadContext` manages ongoing uploads.
public final class HTTPResumableUploadContext: Sendable {
    let origin: String
    let path: String
    let timeout: TimeAmount
    private let uploads: NIOLockedValueBox<[String: HTTPResumableUpload.SendableView]> = .init([:])

    /// Create an `HTTPResumableUploadContext` for use with `HTTPResumableUploadHandler`.
    /// - Parameters:
    ///   - origin: Scheme and authority of the upload server. For example, "https://www.example.com".
    ///   - path: Request path for resumption URLs. `HTTPResumableUploadHandler` intercepts all requests to this path.
    ///   - timeout: Time to wait before failure if the client didn't attempt an upload resumption.
    public init(origin: String, path: String = "/resumable_upload/", timeout: TimeAmount = .hours(1)) {
        self.origin = origin
        self.path = path
        self.timeout = timeout
    }

    func isResumption(path: String) -> Bool {
        path.hasPrefix(self.path)
    }

    private func path(fromToken token: String) -> String {
        "\(self.path)\(token)"
    }

    private func token(fromPath path: String) -> String {
        assert(self.isResumption(path: path))
        return String(path.dropFirst(self.path.count))
    }

    func startUpload(_ upload: HTTPResumableUpload) -> String {
        var random = SystemRandomNumberGenerator()
        let token = "\(random.next())-\(random.next())"
        self.uploads.withLockedValue {
            assert($0[token] == nil)
            $0[token] = upload.sendableView
        }
        return self.path(fromToken: token)
    }

    func stopUpload(_ upload: HTTPResumableUpload) {
        if let path = upload.resumePath {
            let token = token(fromPath: path)
            self.uploads.withLockedValue {
                $0[token] = nil
            }
        }
    }

    func findUpload(path: String) -> HTTPResumableUpload.SendableView? {
        let token = token(fromPath: path)
        return self.uploads.withLockedValue {
            $0[token]
        }
    }
}
