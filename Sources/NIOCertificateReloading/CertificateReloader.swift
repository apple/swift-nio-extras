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

import NIOCore
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
    public struct CertificateReloaderError: Error, Hashable, CustomStringConvertible {
        private enum _Backing: CustomStringConvertible {
            case missingCertificateChain
            case missingPrivateKey

            var description: String {
                switch self {
                case .missingCertificateChain:
                    return "Missing certificate chain"
                case .missingPrivateKey:
                    return "Missing private key"
                }
            }
        }

        private let _backing: _Backing

        private init(backing: _Backing) {
            self._backing = backing
        }

        public var description: String {
            self._backing.description
        }

        /// The given ``CertificateReloader`` could not provide a certificate chain with which to create this config.
        public static var missingCertificateChain: Self { .init(backing: .missingCertificateChain) }

        /// The given ``CertificateReloader`` could not provide a private key with which to create this config.
        public static var missingPrivateKey: Self { .init(backing: .missingPrivateKey) }
    }

    /// Create a ``NIOSSL/TLSConfiguration`` for use with server-side contexts, with certificate reloading enabled.
    /// - Parameter certificateReloader: A ``CertificateReloader`` to watch for certificate and key pair updates.
    /// - Returns: A ``NIOSSL/TLSConfiguration`` for use with server-side contexts, that reloads the certificate and key
    /// used in its SSL handshake.
    /// - Throws: This method will throw if an override isn't present. This may happen if a certificate or private key could not be
    /// loaded from the given paths.
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
        configuration.setCertificateReloader(certificateReloader)
        return configuration
    }

    /// Create a ``NIOSSL/TLSConfiguration`` for use with server-side contexts that expect to validate a client, with
    /// certificate reloading enabled. For servers that don't need mTLS, try ``TLSConfiguration/makeServerConfiguration(certificateReloader:)``.
    /// This configuration is very similar to ``TLSConfiguration/makeServerConfiguration(certificateReloader:)`` but
    /// adds a `trustRoots` requirement. These roots will be used to validate the certificate presented by the peer. It
    /// also sets the `certificateVerification` field to `noHostnameVerification`, which enables verification but
    /// disables any hostname checking, which cannot succeed in a server context.
    ///
    /// - Parameters:
    ///  - certificateReloader: A ``CertificateReloader`` to watch for certificate and key pair updates.
    ///  - trustRoots: The roots used to validate the client certificate.
    /// - Returns: A ``NIOSSL/TLSConfiguration`` for use with server-side contexts, that reloads the certificate and key
    ///   used in its SSL handshake.
    /// - Throws: This method will throw if an override isn't present. This may happen if a certificate or private key
    ///   could not be loaded from the given paths.
    public static func makeServerConfigurationWithMTLS(
        certificateReloader: some CertificateReloader,
        trustRoots: NIOSSLTrustRoots
    ) throws -> Self {
        let override = certificateReloader.sslContextConfigurationOverride

        guard let certificateChain = override.certificateChain else {
            throw CertificateReloaderError.missingCertificateChain
        }

        guard let privateKey = override.privateKey else {
            throw CertificateReloaderError.missingPrivateKey
        }

        var configuration = Self.makeServerConfigurationWithMTLS(
            certificateChain: certificateChain,
            privateKey: privateKey,
            trustRoots: trustRoots
        )
        configuration.setCertificateReloader(certificateReloader)
        return configuration
    }

    /// Create a ``NIOSSL/TLSConfiguration`` for use with client-side contexts, with certificate reloading enabled.
    /// - Parameter certificateReloader: A ``CertificateReloader`` to watch for certificate and key pair updates.
    /// - Returns: A ``NIOSSL/TLSConfiguration`` for use with client-side contexts, that reloads the certificate and key
    /// used in its SSL handshake.
    /// - Throws: This method will throw if an override isn't present. This may happen if a certificate or private key could not be
    /// loaded from the given paths.
    public static func makeClientConfiguration(
        certificateReloader: some CertificateReloader
    ) throws -> Self {
        let override = certificateReloader.sslContextConfigurationOverride

        guard let certificateChain = override.certificateChain else {
            throw CertificateReloaderError.missingCertificateChain
        }

        guard let privateKey = override.privateKey else {
            throw CertificateReloaderError.missingPrivateKey
        }

        var configuration = Self.makeClientConfiguration()
        configuration.certificateChain = certificateChain
        configuration.privateKey = privateKey
        configuration.setCertificateReloader(certificateReloader)
        return configuration
    }

    /// Configure a ``CertificateReloader`` to observe updates for the certificate and key pair used.
    /// - Parameter reloader: A ``CertificateReloader`` to watch for certificate and key pair updates.
    public mutating func setCertificateReloader(_ reloader: some CertificateReloader) {
        self.sslContextCallback = { _, promise in
            promise.succeed(reloader.sslContextConfigurationOverride)
        }
    }
}
