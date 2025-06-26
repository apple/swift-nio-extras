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
import Logging
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
/// key via ``init(refreshInterval:certificateSource:privateKeySource:logger:)``.
/// Simply creating a timed reloader won't validate that the sources provide valid certificate and private key pairs. If you want this to be
/// validated at creation time, you may instead use
/// ``makeReloaderValidatingSources(refreshInterval:certificateSource:privateKeySource:logger:)``.
///
/// You may then set the timed reloader on your ``NIOSSL/TLSConfiguration`` using
/// ``NIOSSL/TLSConfiguration/setCertificateReloader(_:)``:
///
/// ```swift
/// var configuration = TLSConfiguration.makeServerConfiguration(
///     certificateChain: chain,
///     privateKey: key
/// )
/// let reloader = TimedCertificateReloader(
///     refreshInterval: .seconds(500),
///     certificateSource: TimedCertificateReloader.CertificateSource(...),
///     privateKeySource: TimedCertificateReloader.PrivateKeySource(...)
/// )
/// configuration.setCertificateReloader(reloader)
/// ```
///
/// Finally, you must call ``run()`` on the reloader for it to start observing changes.
/// If you want to trigger a manual reload at any point, you may call ``reload()``.
///
/// If you're creating a server configuration, you can instead opt to use
/// ``NIOSSL/TLSConfiguration/makeServerConfiguration(certificateReloader:)``, which will set the initial
/// certificate chain and private key, as well as set the reloader:
///
/// ```swift
/// let configuration = TLSConfiguration.makeServerConfiguration(
///     certificateReloader: reloader
/// )
/// ```
///
/// If you're creating a client configuration, you can instead opt to use
/// ``NIOSSL/TLSConfiguration/makeClientConfiguration(certificateReloader:)`` which will set the reloader:
/// ```swift
/// let configuration = TLSConfiguration.makeClientConfiguration(
///     certificateReloader: reloader
/// )
/// ```
///
/// In both cases, make sure you've either called ``run()`` or created the ``TimedCertificateReloader`` using
/// ``makeReloaderValidatingSources(refreshInterval:certificateSource:privateKeySource:logger:)``
/// _before_ creating the ``NIOSSL/TLSConfiguration``, as otherwise the validation will fail.
///
/// Once the reloader is running, you can manually access its ``sslContextConfigurationOverride`` property to get a
/// `NIOSSLContextConfigurationOverride`, although this will typically not be necessary, as it's the NIO channel that will
/// handle the override when initiating TLS handshakes.
///
/// ```swift
/// try await withThrowingTaskGroup(of: Void.self) { group in
///     group.addTask {
///         reloader.run()
///     }
///     // ...
///     let override = reloader.sslContextConfigurationOverride
///     // ...
/// }
/// ```
///
/// ``TimedCertificateReloader`` conforms to `ServiceLifecycle`'s `Service` protocol, meaning you can simply create
/// the reloader and add it to your `ServiceGroup` without having to manually run it.
///
/// If any errors occur during a reload attempt (such as: being unable to find the file(s) containing the certificate or the key; the format
/// not being recognized or not matching the configured one; not being able to verify a certificate's signature against the given
/// private key; etc), then that attempt will be aborted but the service will keep on trying at the configured interval.
/// The last-valid certificate-key pair (if any) will be returned as the ``sslContextConfigurationOverride``.
#if compiler(>=6.0)
@available(macOS 13, iOS 16, watchOS 9, tvOS 16, macCatalyst 16, visionOS 1, *)
#else
@available(macOS 13, iOS 16, watchOS 9, tvOS 16, macCatalyst 16, *)
#endif
public struct TimedCertificateReloader: CertificateReloader {
    /// The encoding for the certificate or the key.
    public struct Encoding: Sendable, Hashable {
        fileprivate enum _Backing {
            case der
            case pem
        }
        fileprivate let _backing: _Backing

        private init(_ backing: _Backing) {
            self._backing = backing
        }

        /// The encoding of this certificate/key is DER bytes.
        public static var der: Self { .init(.der) }

        /// The encoding of this certificate/key is PEM.
        public static var pem: Self { .init(.pem) }
    }

    /// A location specification for a certificate or key.
    public struct Location: Sendable, CustomStringConvertible {
        fileprivate enum _Backing: CustomStringConvertible {
            case file(path: String)
            case memory(provider: @Sendable () throws -> [UInt8])

            var description: String {
                switch self {
                case .file(let path):
                    return "Filepath: \(path)"
                case .memory:
                    return "<in-memory location>"
                }
            }
        }

        fileprivate let _backing: _Backing

        private init(_ backing: _Backing) {
            self._backing = backing
        }

        public var description: String {
            self._backing.description
        }

        /// This certificate/key can be found at the given filepath.
        /// - Parameter path: The filepath where the certificate/key can be found.
        /// - Returns: A `Location`.
        public static func file(path: String) -> Self { Self(_Backing.file(path: path)) }

        /// This certificate/key is available in memory, and will be provided by the given closure.
        /// - Parameter provider: A closure providing the bytes for the given certificate or key. It may throw if, e.g., a
        /// certificate or key isn't available.
        /// - Returns: A `Location`.
        public static func memory(provider: @Sendable @escaping () throws -> [UInt8]) -> Self {
            Self(_Backing.memory(provider: provider))
        }
    }

    /// A description of a certificate, in terms of its ``TimedCertificateReloader/Location`` and
    /// ``TimedCertificateReloader/Encoding``.
    public struct CertificateSource: Sendable {

        /// The certificate's ``TimedCertificateReloader/Location``.
        public var location: Location

        /// The certificate's ``TimedCertificateReloader/Encoding``.
        public var format: Encoding

        /// Initialize a new ``TimedCertificateReloader/CertificateSource``.
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
    public struct PrivateKeySource: Sendable {

        /// The key's ``TimedCertificateReloader/Location``.
        public var location: Location

        /// The key's ``TimedCertificateReloader/Encoding``.
        public var format: Encoding

        /// Initialize a new ``TimedCertificateReloader/PrivateKeySource``.
        /// - Parameters:
        ///   - location: A ``TimedCertificateReloader/Location``.
        ///   - format: A ``TimedCertificateReloader/Encoding``.
        public init(location: Location, format: Encoding) {
            self.location = location
            self.format = format
        }
    }

    /// Errors specific to the ``TimedCertificateReloader``.
    public struct Error: Swift.Error, Hashable, CustomStringConvertible {
        private enum _Backing: Hashable, CustomStringConvertible {
            case certificatePathNotFound(String)
            case privateKeyPathNotFound(String)
            case certificateLoadingError(reason: String)
            case privateKeyLoadingError(reason: String)
            case publicKeyMismatch

            var description: String {
                switch self {
                case .certificatePathNotFound(let path):
                    return "Certificate path not found: \(path)"
                case .privateKeyPathNotFound(let path):
                    return "Private key path not found: \(path)"
                case let .certificateLoadingError(reason):
                    return "Failed to load certificate: \(reason)"
                case let .privateKeyLoadingError(reason):
                    return "Failed to load private key: \(reason)"
                case .publicKeyMismatch:
                    return
                        """
                        The public key derived from the private key does not match the public key in the certificate. \n
                        This may occur if the certificate and key were reloaded inconsistently or during an update in progress.
                        """
                }
            }
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

        /// Failed to load the certificate.
        /// - Parameter reason: A description of the error occurred.
        /// - Returns: A ``TimedCertificateReloader/Error``.
        public static func certificateLoadingError(reason: String) -> Self {
            Self(.certificateLoadingError(reason: reason))
        }

        /// Failed to load the private key.
        /// - Parameter reason: A description of the error occurred.
        /// - Returns: A ``TimedCertificateReloader/Error``.
        public static func privateKeyLoadingError(reason: String) -> Self {
            Self(.privateKeyLoadingError(reason: reason))
        }

        /// The private key does not match the provided certificate.
        public static var publicKeyMismatch: Self {
            Self(.publicKeyMismatch)
        }

        public var description: String {
            self._backing.description
        }
    }

    private struct CertificateKeyPair {
        var certificates: [NIOSSLCertificateSource]
        var privateKey: NIOSSLPrivateKeySource
    }

    private let refreshInterval: Duration
    private let certificateSource: CertificateSource
    private let privateKeySource: PrivateKeySource
    private let state: NIOLockedValueBox<CertificateKeyPair?>
    private let logger: Logger?

    /// A `NIOSSLContextConfigurationOverride` that will be used as part of the NIO application's TLS configuration.
    /// Its certificate and private key will be kept up-to-date via the reload mechanism the ``TimedCertificateReloader``
    /// implementation provides.
    /// - Note: If no reload attempt has yet been tried (either by creating the reloader with
    /// ``makeReloaderValidatingSources(refreshInterval:certificateSource:privateKeySource:logger:)``,
    /// manually calling ``reload()``, or by calling ``run()``), `NIOSSLContextConfigurationOverride/noChanges`
    /// will be returned.
    public var sslContextConfigurationOverride: NIOSSLContextConfigurationOverride {
        get {
            guard let certificateKeyPair = self.state.withLockedValue({ $0 }) else {
                return .noChanges
            }
            var override = NIOSSLContextConfigurationOverride()
            override.certificateChain = certificateKeyPair.certificates
            override.privateKey = certificateKeyPair.privateKey
            return override
        }
    }

    /// Initialize a new ``TimedCertificateReloader``.
    /// - Important: ``TimedCertificateReloader/sslContextConfigurationOverride`` will return
    /// `NIOSSLContextConfigurationOverride/noChanges` until ``TimedCertificateReloader/run()`` or
    /// ``TimedCertificateReloader/reload()`` are called.
    /// - Parameters:
    ///   - refreshInterval: The interval at which attempts to update the certificate and private key should be made.
    ///   - certificateSource: A ``TimedCertificateReloader/CertificateSource``.
    ///   - privateKeySource: A ``TimedCertificateReloader/PrivateKeySource``.
    ///   - logger: An optional logger.
    public init(
        refreshInterval: Duration,
        certificateSource: CertificateSource,
        privateKeySource: PrivateKeySource,
        logger: Logger? = nil
    ) {
        self.refreshInterval = refreshInterval
        self.certificateSource = certificateSource
        self.privateKeySource = privateKeySource
        self.state = NIOLockedValueBox(nil)
        self.logger = logger
    }

    /// Initialize a new ``TimedCertificateReloader``, and attempt to reload the certificate and private key pair from the given
    /// sources. If the reload fails (because e.g. the paths aren't valid), this method will throw.
    /// - Important: If this method does not throw, it is guaranteed that
    /// ``TimedCertificateReloader/sslContextConfigurationOverride`` will contain the configured certificate and
    /// private key pair, even before the first reload is triggered or ``TimedCertificateReloader/run()`` is called.
    /// - Parameters:
    ///   - refreshInterval: The interval at which attempts to update the certificate and private key should be made.
    ///   - certificateSource: A ``TimedCertificateReloader/CertificateSource``.
    ///   - privateKeySource: A ``TimedCertificateReloader/PrivateKeySource``.
    ///   - logger: An optional logger.
    /// - Returns: The newly created ``TimedCertificateReloader``.
    /// - Throws: If either the certificate or private key sources cannot be loaded, an error will be thrown.
    public static func makeReloaderValidatingSources(
        refreshInterval: Duration,
        certificateSource: CertificateSource,
        privateKeySource: PrivateKeySource,
        logger: Logger? = nil
    ) throws -> Self {
        let reloader = Self.init(
            refreshInterval: refreshInterval,
            certificateSource: certificateSource,
            privateKeySource: privateKeySource,
            logger: logger
        )
        try reloader.reload()
        return reloader
    }

    /// A long-running method to run the ``TimedCertificateReloader`` and start observing updates for the certificate and
    /// private key pair.
    /// - Important: You *must* call this method to get certificate and key updates.
    public func run() async throws {
        for try await _ in AsyncTimerSequence.repeating(every: self.refreshInterval).cancelOnGracefulShutdown() {
            do {
                try self.reload()
            } catch {
                self.logger?.debug(
                    "Failed to reload certificate and private key.",
                    metadata: [
                        "error": "\(error)",
                        "certificatePath": "\(self.certificateSource.location)",
                        "privateKeyPath": "\(self.privateKeySource.location)",
                    ]
                )
            }
        }
    }

    /// Manually attempt a certificate and private key pair update.
    public func reload() throws {
        let certificateBytes = try self.loadCertificate()
        let keyBytes = try self.loadPrivateKey()

        let certificates = try self.parseCertificates(from: certificateBytes)
        let key = try self.parsePrivateKey(from: keyBytes)

        guard let firstCertificate = certificates.first else {
            throw Error.certificateLoadingError(reason: "The provided file does not contain any certificates.")
        }

        guard key.publicKey == firstCertificate.publicKey else {
            throw Error.publicKeyMismatch
        }

        try self.attemptToUpdatePair(certificates: certificates, key: key)
    }

    private func loadCertificate() throws -> [UInt8] {
        let certificateBytes: [UInt8]
        switch self.certificateSource.location._backing {
        case .file(let path):
            guard let bytes = FileManager.default.contents(atPath: path) else {
                throw Error.certificatePathNotFound(path)
            }
            certificateBytes = Array(bytes)

        case .memory(let bytesProvider):
            certificateBytes = try bytesProvider()
        }
        return certificateBytes
    }

    private func loadPrivateKey() throws -> [UInt8] {
        let keyBytes: [UInt8]
        switch self.privateKeySource.location._backing {
        case .file(let path):
            guard let bytes = FileManager.default.contents(atPath: path) else {
                throw Error.privateKeyPathNotFound(path)
            }
            keyBytes = Array(bytes)

        case .memory(let bytesProvider):
            keyBytes = try bytesProvider()
        }
        return keyBytes
    }

    private func parseCertificates(from certificateBytes: [UInt8]) throws -> [Certificate] {
        let certificates: [Certificate]
        switch self.certificateSource.format._backing {
        case .der:
            certificates = [try Certificate(derEncoded: certificateBytes)]

        case .pem:
            guard let pemString = String(bytes: certificateBytes, encoding: .utf8) else {
                throw Error.certificateLoadingError(reason: "Certificate data is not valid UTF-8.")
            }

            certificates = try PEMDocument.parseMultiple(pemString: pemString)
                .map { try Certificate(pemDocument: $0) }
        }
        return certificates
    }

    private func parsePrivateKey(from keyBytes: [UInt8]) throws -> Certificate.PrivateKey {
        let key: Certificate.PrivateKey
        switch self.privateKeySource.format._backing {
        case .der:
            key = try Certificate.PrivateKey(derBytes: keyBytes)

        case .pem:
            guard let pemString = String(bytes: keyBytes, encoding: .utf8) else {
                throw Error.privateKeyLoadingError(reason: "Private Key data is not valid UTF-8.")
            }
            key = try Certificate.PrivateKey(pemEncoded: pemString)
        }
        return key
    }

    private func attemptToUpdatePair(certificates: [Certificate], key: Certificate.PrivateKey) throws {
        let nioSSLCertificates =
            try certificates
            .map {
                try NIOSSLCertificate(
                    bytes: $0.serializeAsPEM().derBytes,
                    format: .der
                )
            }
        let nioSSLPrivateKey = try NIOSSLPrivateKey(
            bytes: key.serializeAsPEM().derBytes,
            format: .der
        )
        self.state.withLockedValue {
            $0 = CertificateKeyPair(
                certificates: nioSSLCertificates.map { .certificate($0) },
                privateKey: .privateKey(nioSSLPrivateKey)
            )
        }
    }
}

#if compiler(>=6.0)
@available(macOS 13, iOS 16, watchOS 9, tvOS 16, macCatalyst 16, visionOS 1, *)
#else
@available(macOS 13, iOS 16, watchOS 9, tvOS 16, macCatalyst 16, *)
#endif
extension TimedCertificateReloader: Service {}
