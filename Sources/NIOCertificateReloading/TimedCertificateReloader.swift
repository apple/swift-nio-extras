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

import AsyncAlgorithms
import NIOConcurrencyHelpers
import NIOSSL
import ServiceLifecycle
import SwiftASN1
import X509

import struct NIOCore.TimeAmount

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A ``TimedCertificateReloader`` is an implementation of a ``CertificateReloader``, where the certificate and private
/// key pair is updated at a fixed interval from the file path or memory location configured.
///
/// You initialize a ``TimedCertificateReloader`` by providing a refresh interval, and locations for the certificate and the private
/// key. You must then call ``run()`` on this reloader for it to start observing changes.
/// Once the reloader is running, call ``sslContextConfigurationOverride`` to get a
/// `NIOSSLContextConfigurationOverride` which can be set on NIO's `TLSConfiguration`: this will keep the certificate
/// and private key pair up to date.
/// You may instead call  ``NIOSSL/TLSConfiguration/setCertificateReloader(_:)`` to get a
/// ``NIOSSL/TLSConfiguration`` with a configured reloader.
///
/// If any errors occur during a reload attempt (such as: being unable to find the file(s) containing the certificate or the key; the format
/// not being recognized or not matching the configured one; not being able to verify a certificate's signature against the given
/// private key; etc), then that attempt will be aborted but the service will keep on trying at the configured interval.
/// The last-valid certificate-key pair (if any) will be returned as the ``sslContextConfigurationOverride``.
@available(macOS 13, iOS 14, tvOS 14, watchOS 7, *)
public struct TimedCertificateReloader: CertificateReloader {
    /// The encoding for the certificate or the key.
    public struct Encoding: Sendable, Equatable {
        fileprivate enum _Backing {
            case der
            case pem
        }
        fileprivate let _backing: _Backing

        private init(_ backing: _Backing) {
            self._backing = backing
        }

        /// The encoding of this certificate/key is DER bytes.
        public static let der = Encoding(.der)

        /// The encoding of this certificate/key is PEM.
        public static let pem = Encoding(.pem)
    }

    /// A location specification for a certificate or key.
    public struct Location: Sendable {
        fileprivate enum _Backing {
            case file(path: String)
            case memory(provider: @Sendable () -> [UInt8]?)
        }

        fileprivate let _backing: _Backing

        private init(_ backing: _Backing) {
            self._backing = backing
        }

        /// This certificate/key can be found at the given filepath.
        /// - Parameter path: The filepath where the certificate/key can be found.
        /// - Returns: A `Location`.
        public static func file(path: String) -> Self { Self(_Backing.file(path: path)) }

        /// This certificate/key is available in memory, and will be provided by the given closure.
        /// - Parameter provider: A closure providing the bytes for the given certificate or key. This closure should return
        /// `nil` if a certificate/key isn't currently available for whatever reason.
        /// - Returns: A `Location`.
        public static func memory(provider: @Sendable @escaping () -> [UInt8]?) -> Self {
            Self(_Backing.memory(provider: provider))
        }
    }

    /// A description of a certificate, in terms of its ``TimedCertificateReloader/Location`` and
    /// ``TimedCertificateReloader/Encoding``.
    public struct CertificateDescription: Sendable {

        /// The certificate's ``TimedCertificateReloader/Location``.
        public var location: Location

        /// The certificate's ``TimedCertificateReloader/Encoding``.
        public var format: Encoding

        /// Initialize a new ``TimedCertificateReloader/CertificateDescription``.
        /// - Parameters:
        ///   - location: A ``TimedCertificateReloader/Location``.
        ///   - format: A ``TimedCertificateReloader/Encoding``.
        public init(location: Location, format: Encoding) {
            self.location = location
            self.format = format
        }
    }

    /// A description of a private key, in terms of its ``TimedCertificateReloader/Location`` and
    /// ``TimedCertificateReloader/Encoding``.
    public struct PrivateKeyDescription: Sendable {

        /// The key's ``TimedCertificateReloader/Location``.
        public var location: Location

        /// The key's ``TimedCertificateReloader/Encoding``.
        public var format: Encoding

        /// Initialize a new ``TimedCertificateReloader/PrivateKeyDescription``.
        /// - Parameters:
        ///   - location: A ``TimedCertificateReloader/Location``.
        ///   - format: A ``TimedCertificateReloader/Encoding``.
        public init(location: Location, format: Encoding) {
            self.location = location
            self.format = format
        }
    }

    /// Errors specific to the ``TimedCertificateReloader``.
    public struct Error: Swift.Error {
        private enum _Backing {
            case certificatePathNotFound(String)
            case privateKeyPathNotFound(String)
        }

        private let _backing: _Backing

        private init(_ backing: _Backing) {
            self._backing = backing
        }
        
        /// The file path given for the certificate cannot be found.
        /// - Parameter path: The file path given for the certificate.
        /// - Returns: A ``TimedCertificateReloader/Error``.
        public static func certificatePathNotFound(_ path: String) -> Self {
            Self(.certificatePathNotFound(path))
        }

        /// The file path given for the private key cannot be found.
        /// - Parameter path: The file path given for the private key.
        /// - Returns: A ``TimedCertificateReloader/Error``.
        public static func privateKeyPathNotFound(_ path: String) -> Self {
            Self(.privateKeyPathNotFound(path))
        }
    }

    private struct CertificateKeyPair {
        var certificate: NIOSSLCertificateSource
        var privateKey: NIOSSLPrivateKeySource
    }

    private let refreshInterval: Duration
    private let certificateDescription: CertificateDescription
    private let privateKeyDescription: PrivateKeyDescription
    private let state: NIOLockedValueBox<CertificateKeyPair?>

    /// A `NIOSSLContextConfigurationOverride` that will be used as part of the NIO application's TLS configuration.
    /// Its certificate and private key will be kept up-to-date via the reload mechanism the ``TimedCertificateReloader``
    /// implementation provides.
    public var sslContextConfigurationOverride: NIOSSLContextConfigurationOverride {
        get {
            var override = NIOSSLContextConfigurationOverride()
            guard let certificateKeyPair = self.state.withLockedValue({ $0 }) else {
                return override
            }
            override.certificateChain = [certificateKeyPair.certificate]
            override.privateKey = certificateKeyPair.privateKey
            return override
        }
    }

    /// Initialize a new ``TimedCertificateReloader``.
    /// - Parameters:
    ///   - refreshInterval: The interval at which attempts to update the certificate and private key should be made.
    ///   - certificateDescription: A ``CertificateDescription``.
    ///   - privateKeyDescription: A ``PrivateKeyDescription``.
    public init(
        refreshInterval: TimeAmount,
        certificateDescription: CertificateDescription,
        privateKeyDescription: PrivateKeyDescription
    ) {
        self.init(
            refreshInterval: Duration(refreshInterval),
            certificateDescription: certificateDescription,
            privateKeyDescription: privateKeyDescription
        )
    }

    /// Attempt to initialize a new ``TimedCertificateReloader``, but throw if the given certificate and private keys cannot be
    /// loaded.
    /// - Parameters:
    ///   - refreshInterval: The interval at which attempts to update the certificate and private key should be made.
    ///   - validatingCertificateDescription: A ``CertificateDescription``.
    ///   - validatingPrivateKeyDescription: A ``PrivateKeyDescription``.
    /// - Throws: If the certificate or private key cannot be loaded.
    public init(
        refreshInterval: TimeAmount,
        validatingCertificateDescription: CertificateDescription,
        validatingPrivateKeyDescription: PrivateKeyDescription
    ) throws {
        try self.init(
            refreshInterval: Duration(refreshInterval),
            validatingCertificateDescription: validatingCertificateDescription,
            validatingPrivateKeyDescription: validatingPrivateKeyDescription
        )
    }

    /// Initialize a new ``TimedCertificateReloader``.
    /// - Parameters:
    ///   - refreshInterval: The interval at which attempts to update the certificate and private key should be made.
    ///   - certificateDescription: A ``CertificateDescription``.
    ///   - privateKeyDescription: A ``PrivateKeyDescription``.
    public init(
        refreshInterval: Duration,
        certificateDescription: CertificateDescription,
        privateKeyDescription: PrivateKeyDescription
    ) {
        self.refreshInterval = refreshInterval
        self.certificateDescription = certificateDescription
        self.privateKeyDescription = privateKeyDescription
        self.state = NIOLockedValueBox(nil)

        // Immediately try to load the configured cert and key to avoid having to wait for the first
        // reload loop to run.
        // We ignore errors because this initializer tolerates not finding the certificate and/or
        // private key on first load.
        try? self.reloadPair()
    }

    /// Attempt to initialize a new ``TimedCertificateReloader``, but throw if the given certificate and private keys cannot be
    /// loaded.
    /// - Parameters:
    ///   - refreshInterval: The interval at which attempts to update the certificate and private key should be made.
    ///   - validatingCertificateDescription: A ``CertificateDescription``.
    ///   - validatingPrivateKeyDescription: A ``PrivateKeyDescription``.
    /// - Throws: If the certificate or private key cannot be loaded.
    public init(
        refreshInterval: Duration,
        validatingCertificateDescription: CertificateDescription,
        validatingPrivateKeyDescription: PrivateKeyDescription
    ) throws {
        self.refreshInterval = refreshInterval
        self.certificateDescription = validatingCertificateDescription
        self.privateKeyDescription = validatingPrivateKeyDescription
        self.state = NIOLockedValueBox(nil)

        // Immediately try to load the configured cert and key to avoid having to wait for the first
        // reload loop to run.
        try self.reloadPair()
    }

    /// A long-running method to run the ``TimedCertificateReloader`` and start observing updates for the certificate and
    /// private key pair.
    /// - Important: You *must* call this method to get certificate and key updates.
    public func run() async throws {
        for try await _ in AsyncTimerSequence.repeating(every: self.refreshInterval).cancelOnGracefulShutdown() {
            // We don't want to throw out of this method so simply ignore errors thrown from `reloadPair`.
            try? self.reloadPair()
        }
    }

    private func reloadPair() throws {
        if let certificateBytes = try self.loadCertificate(),
           let keyBytes = try self.loadPrivateKey(),
           let certificate = try self.parseCertificate(from: certificateBytes),
           let key = try self.parsePrivateKey(from: keyBytes),
           key.publicKey.isValidSignature(certificate.signature, for: certificate)
        {
            try self.attemptToUpdatePair(certificate: certificate, key: key)
        }
    }

    private func loadCertificate() throws -> [UInt8]? {
        let certificateBytes: [UInt8]?
        switch self.certificateDescription.location._backing {
        case .file(let path):
            guard let bytes = FileManager.default.contents(atPath: path) else {
                throw Error.certificatePathNotFound(path)
            }
            certificateBytes = Array(bytes)

        case .memory(let bytesProvider):
            certificateBytes = bytesProvider()
        }
        return certificateBytes
    }

    private func loadPrivateKey() throws -> [UInt8]? {
        let keyBytes: [UInt8]?
        switch self.privateKeyDescription.location._backing {
        case .file(let path):
            guard let bytes = FileManager.default.contents(atPath: path) else {
                throw Error.privateKeyPathNotFound(path)
            }
            keyBytes = Array(bytes)

        case .memory(let bytesProvider):
            keyBytes = bytesProvider()
        }
        return keyBytes
    }

    private func parseCertificate(from certificateBytes: [UInt8]) throws -> Certificate? {
        let certificate: Certificate?
        switch self.certificateDescription.format._backing {
        case .der:
            certificate = try Certificate(derEncoded: certificateBytes)

        case .pem:
            certificate = try String(bytes: certificateBytes, encoding: .utf8)
                .flatMap { try Certificate(pemEncoded: $0) }
        }
        return certificate
    }

    private func parsePrivateKey(from keyBytes: [UInt8]) throws -> Certificate.PrivateKey? {
        let key: Certificate.PrivateKey?
        switch self.privateKeyDescription.format._backing {
        case .der:
            key = try Certificate.PrivateKey(derBytes: keyBytes)

        case .pem:
            key = try String(bytes: keyBytes, encoding: .utf8)
                .flatMap { try Certificate.PrivateKey(pemEncoded: $0) }
        }
        return key
    }

    private func attemptToUpdatePair(certificate: Certificate, key: Certificate.PrivateKey) throws {
        let nioSSLCertificate = try NIOSSLCertificate(
            bytes: certificate.serializeAsPEM().derBytes,
            format: .der
        )
        let nioSSLPrivateKey = try NIOSSLPrivateKey(
            bytes: key.serializeAsPEM().derBytes,
            format: .der
        )
        self.state.withLockedValue {
            $0 = CertificateKeyPair(
                certificate: .certificate(nioSSLCertificate),
                privateKey: .privateKey(nioSSLPrivateKey)
            )
        }
    }
}

@available(macOS 13, iOS 14, tvOS 14, watchOS 7, *)
extension TimedCertificateReloader: Service {}
