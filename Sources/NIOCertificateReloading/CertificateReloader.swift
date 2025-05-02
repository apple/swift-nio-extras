//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2025 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOSSL

/// A protocol that defines a certificate reloader.
///
/// A certificate reloader is a service that can provide you with updated versions of a certificate and private key pair, in
/// the form of a `NIOSSLContextConfigurationOverride`, which will be used when performing a TLS handshake in NIO.
/// Each implementation can choose how to observe for changes, but they all require an ``sslContextConfigurationOverride``
/// to be exposed.
@available(macOS 11.0, iOS 14, tvOS 14, watchOS 7, *)
public protocol CertificateReloader: Sendable {
    /// A `NIOSSLContextConfigurationOverride` that will be used as part of the NIO application's TLS configuration.
    /// Its certificate and private key will be kept up-to-date via whatever mechanism the specific ``CertificateReloader``
    /// implementation provides.
    var sslContextConfigurationOverride: NIOSSLContextConfigurationOverride { get }
}

extension TLSConfiguration {
    /// Configure a ``CertificateReloader`` to observe updates for the certificate and key pair used.
    /// - Parameter reloader: A ``CertificateReloader`` to watch for certificate and key pair updates.
    /// - Returns: A `TLSConfiguration` that reloads the certificate and key used in its SSL handshake.
    @available(macOS 11.0, iOS 14, tvOS 14, watchOS 7, *)
    mutating public func setCertificateReloader(_ reloader: some CertificateReloader) -> Self {
        self.sslContextCallback = { _, promise in
            promise.succeed(reloader.sslContextConfigurationOverride)
        }
        return self
    }
}
