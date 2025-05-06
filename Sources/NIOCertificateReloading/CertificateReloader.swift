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
public protocol CertificateReloader: Sendable {
    /// A `NIOSSLContextConfigurationOverride` that will be used as part of the NIO application's TLS configuration.
    /// Its certificate and private key will be kept up-to-date via whatever mechanism the specific ``CertificateReloader``
    /// implementation provides.
    var sslContextConfigurationOverride: NIOSSLContextConfigurationOverride { get }
}

extension TLSConfiguration {
    /// Errors thrown when creating a ``NIOSSL/TLSConfiguration`` with a ``CertificateReloader``.
    public struct CertificateReloaderError: Error {
        private enum _Backing {
            case missingCertificateChain
            case missingPrivateKey
        }

        private let backing: _Backing

        private init(backing: _Backing) {
            self.backing = backing
        }
        
        /// The given ``CertificateReloader`` could not provide a certificate chain with which to create this config.
        public static let missingCertificateChain: Self = .init(backing: .missingCertificateChain)

        /// The given ``CertificateReloader`` could not provide a private key with which to create this config.
        public static let missingPrivateKey: Self = .init(backing: .missingPrivateKey)
    }
    
    /// Create a ``NIOSSL/TLSConfiguration`` for use with server-side contexts, with certificate reloading enabled.
    /// - Parameter certificateReloader: A ``CertificateReloader`` to watch for certificate and key pair updates.
    /// - Returns: A ``NIOSSL/TLSConfiguration`` for use with server-side contexts, that reloads the certificate and key
    /// used in its SSL handshake.
    public static func makeServerConfiguration(
        certificateReloader: some CertificateReloader
    ) throws -> Self {
        let override = certificateReloader.sslContextConfigurationOverride

        guard let certificateChain = override.certificateChain else {
            throw CertificateReloaderError.missingCertificateChain
        }

        guard let privateKey = override.privateKey else {
            throw CertificateReloaderError.missingPrivateKey
        }

        var configuration = Self.makeServerConfiguration(
            certificateChain: certificateChain,
            privateKey: privateKey
        )
        return configuration.setCertificateReloader(certificateReloader)
    }

    /// Configure a ``CertificateReloader`` to observe updates for the certificate and key pair used.
    /// - Parameter reloader: A ``CertificateReloader`` to watch for certificate and key pair updates.
    /// - Returns: A ``NIOSSL/TLSConfiguration`` that reloads the certificate and key used in its SSL handshake.
    mutating public func setCertificateReloader(_ reloader: some CertificateReloader) -> Self {
        self.sslContextCallback = { _, promise in
            promise.succeed(reloader.sslContextConfigurationOverride)
        }
        return self
    }
}
