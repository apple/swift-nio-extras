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

@preconcurrency import Crypto
import NIOCertificateReloading
import NIOConcurrencyHelpers
import NIOSSL
import SwiftASN1
import X509
import XCTest

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

final class TimedCertificateReloaderTests: XCTestCase {
    func testCertificatePathDoesNotExist() async throws {
        try await runTimedCertificateReloaderTest(
            certificate: .init(location: .file(path: "doesnotexist"), format: .der),
            privateKey: .init(
                location: .memory(provider: { Array(Self.samplePrivateKey.derRepresentation) }),
                format: .der
            ),
            validateSources: false
        ) { reloader in
            let override = reloader.sslContextConfigurationOverride
            XCTAssertNil(override.certificateChain)
            XCTAssertNil(override.privateKey)
        }
    }

    func testCertificatePathDoesNotExist_ValidatingSource() async throws {
        do {
            try await runTimedCertificateReloaderTest(
                certificate: .init(location: .file(path: "doesnotexist"), format: .der),
                privateKey: .init(
                    location: .memory(provider: { Array(Self.samplePrivateKey.derRepresentation) }),
                    format: .der
                )
            ) { _ in
                XCTFail("Test should have failed before reaching this point.")
            }
        } catch {
            XCTAssertEqual(
                error as? TimedCertificateReloader.Error,
                TimedCertificateReloader.Error.certificatePathNotFound("doesnotexist")
            )
        }
    }

    func testKeyPathDoesNotExist() async throws {
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { try Self.sampleCert.serializeAsPEM().derBytes }),
                format: .der
            ),
            privateKey: .init(
                location: .file(path: "doesnotexist"),
                format: .der
            ),
            validateSources: false
        ) { reloader in
            let override = reloader.sslContextConfigurationOverride
            XCTAssertNil(override.certificateChain)
            XCTAssertNil(override.privateKey)
        }
    }

    func testKeyPathDoesNotExist_ValidatingSource() async throws {
        do {
            try await runTimedCertificateReloaderTest(
                certificate: .init(
                    location: .memory(provider: { try Self.sampleCert.serializeAsPEM().derBytes }),
                    format: .der
                ),
                privateKey: .init(
                    location: .file(path: "doesnotexist"),
                    format: .der
                )
            ) { _ in
                XCTFail("Test should have failed before reaching this point.")
            }
        } catch {
            XCTAssertEqual(
                error as? TimedCertificateReloader.Error,
                TimedCertificateReloader.Error.privateKeyPathNotFound("doesnotexist")
            )
        }
    }

    func testCertificateIsInUnexpectedFormat_FromMemory() async throws {
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { try Self.sampleCert.serializeAsPEM().derBytes }),
                format: .pem
            ),
            privateKey: .init(
                location: .memory(provider: { Array(Self.samplePrivateKey.derRepresentation) }),
                format: .der
            )
        ) { reloader in
            let override = reloader.sslContextConfigurationOverride
            XCTAssertNil(override.certificateChain)
            XCTAssertNil(override.privateKey)
        }
    }

    private func createTempFile(contents: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString
        let fileURL = directory.appendingPathComponent(filename)
        guard FileManager.default.createFile(atPath: fileURL.path, contents: contents) else {
            throw TestError.couldNotCreateFile
        }
        return fileURL
    }

    func testCertificateIsInUnexpectedFormat_FromFile() async throws {
        let certBytes = try Self.sampleCert.serializeAsPEM().derBytes
        let file = try self.createTempFile(contents: Data(certBytes))
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .file(path: file.path),
                format: .pem
            ),
            privateKey: .init(
                location: .memory(provider: { Array(Self.samplePrivateKey.derRepresentation) }),
                format: .der
            )
        ) { reloader in
            let override = reloader.sslContextConfigurationOverride
            XCTAssertNil(override.certificateChain)
            XCTAssertNil(override.privateKey)
        }
    }

    func testKeyIsInUnexpectedFormat_FromMemory() async throws {
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { try Self.sampleCert.serializeAsPEM().derBytes }),
                format: .der
            ),
            privateKey: .init(
                location: .memory(provider: { Array(Self.samplePrivateKey.derRepresentation) }),
                format: .pem
            )
        ) { reloader in
            let override = reloader.sslContextConfigurationOverride
            XCTAssertNil(override.certificateChain)
            XCTAssertNil(override.privateKey)
        }
    }

    func testKeyIsInUnexpectedFormat_FromFile() async throws {
        let keyBytes = Self.samplePrivateKey.derRepresentation
        let file = try self.createTempFile(contents: keyBytes)
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { try Self.sampleCert.serializeAsPEM().derBytes }),
                format: .der
            ),
            privateKey: .init(
                location: .file(path: file.path),
                format: .pem
            )
        ) { reloader in
            let override = reloader.sslContextConfigurationOverride
            XCTAssertNil(override.certificateChain)
            XCTAssertNil(override.privateKey)
        }
    }

    func testCertificateAndKeyDoNotMatch() async throws {
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { try Self.sampleCert.serializeAsPEM().derBytes }),
                format: .der
            ),
            privateKey: .init(
                location: .memory(provider: { Array(P384.Signing.PrivateKey().derRepresentation) }),
                format: .der
            )
        ) { reloader in
            let override = reloader.sslContextConfigurationOverride
            XCTAssertNil(override.certificateChain)
            XCTAssertNil(override.privateKey)
        }
    }

    enum TestError: Error {
        case emptyCertificate
        case emptyPrivateKey
        case couldNotCreateFile
    }

    func testReloadSuccessfully_FromMemory() async throws {
        let certificateBox: NIOLockedValueBox<[UInt8]> = NIOLockedValueBox([])
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: {
                    let cert = certificateBox.withLockedValue({ $0 })
                    if cert.isEmpty {
                        throw TestError.emptyCertificate
                    }
                    return cert
                }),
                format: .der
            ),
            privateKey: .init(
                location: .memory(provider: { Array(Self.samplePrivateKey.derRepresentation) }),
                format: .der
            ),
            // We need to disable validation because the provider will initially be empty.
            validateSources: false
        ) { reloader in
            // On first attempt, we should have no certificate or private key overrides available,
            // since the certificate box is empty.
            var override = reloader.sslContextConfigurationOverride
            XCTAssertNil(override.certificateChain)
            XCTAssertNil(override.privateKey)

            // Update the box to contain a valid certificate.
            certificateBox.withLockedValue({ $0 = try! Self.sampleCert.serializeAsPEM().derBytes })

            // Give the reload loop some time to run and update the cert-key pair.
            try await Task.sleep(for: .milliseconds(100), tolerance: .zero)

            // Now the overrides should be present.
            override = reloader.sslContextConfigurationOverride
            XCTAssertEqual(
                override.certificateChain,
                [.certificate(try .init(bytes: Self.sampleCert.serializeAsPEM().derBytes, format: .der))]
            )
            XCTAssertEqual(
                override.privateKey,
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey.derRepresentation), format: .der))
            )
        }
    }

    func testReloadSuccessfully_FromFile() async throws {
        // Start with empty files.
        let certificateFile = try self.createTempFile(contents: Data())
        let privateKeyFile = try self.createTempFile(contents: Data())
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .file(path: certificateFile.path),
                format: .der
            ),
            privateKey: .init(
                location: .file(path: privateKeyFile.path),
                format: .der
            ),
            // We need to disable validation because the files will not initially have any contents.
            validateSources: false
        ) { reloader in
            // On first attempt, we should have no certificate or private key overrides available,
            // since the certificate box is empty.
            var override = reloader.sslContextConfigurationOverride
            XCTAssertNil(override.certificateChain)
            XCTAssertNil(override.privateKey)

            // Update the files to contain data
            try Data(try Self.sampleCert.serializeAsPEM().derBytes).write(to: certificateFile)
            try Self.samplePrivateKey.derRepresentation.write(to: privateKeyFile)

            // Give the reload loop some time to run and update the cert-key pair.
            try await Task.sleep(for: .milliseconds(100), tolerance: .zero)

            // Now the overrides should be present.
            override = reloader.sslContextConfigurationOverride
            XCTAssertEqual(
                override.certificateChain,
                [.certificate(try .init(bytes: Self.sampleCert.serializeAsPEM().derBytes, format: .der))]
            )
            XCTAssertEqual(
                override.privateKey,
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey.derRepresentation), format: .der))
            )
        }
    }

    func testCertificateNotFoundAtReload() async throws {
        let certificateBox: NIOLockedValueBox<[UInt8]> = NIOLockedValueBox(
            try! Self.sampleCert.serializeAsPEM().derBytes
        )
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: {
                    let cert = certificateBox.withLockedValue({ $0 })
                    if cert.isEmpty {
                        throw TestError.emptyCertificate
                    }
                    return cert
                }),
                format: .der
            ),
            privateKey: .init(
                location: .memory(provider: { Array(Self.samplePrivateKey.derRepresentation) }),
                format: .der
            )
        ) { reloader in
            // On first attempt, the overrides should be correctly present.
            var override = reloader.sslContextConfigurationOverride
            XCTAssertEqual(
                override.certificateChain,
                [.certificate(try .init(bytes: Self.sampleCert.serializeAsPEM().derBytes, format: .der))]
            )
            XCTAssertEqual(
                override.privateKey,
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey.derRepresentation), format: .der))
            )

            // Update the box to contain empty bytes: this will cause the provider to throw.
            certificateBox.withLockedValue({ $0 = [] })

            // Give the reload loop some time to run and update the cert-key pair.
            try await Task.sleep(for: .milliseconds(100), tolerance: .zero)

            // We should still be offering the previously valid cert-key pair.
            override = reloader.sslContextConfigurationOverride
            XCTAssertEqual(
                override.certificateChain,
                [.certificate(try .init(bytes: Self.sampleCert.serializeAsPEM().derBytes, format: .der))]
            )
            XCTAssertEqual(
                override.privateKey,
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey.derRepresentation), format: .der))
            )
        }
    }

    func testKeyNotFoundAtReload() async throws {
        let keyBox: NIOLockedValueBox<[UInt8]> = NIOLockedValueBox(
            Array(Self.samplePrivateKey.derRepresentation)
        )
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { try Self.sampleCert.serializeAsPEM().derBytes }),
                format: .der
            ),
            privateKey: .init(
                location: .memory(provider: {
                    let key = keyBox.withLockedValue({ $0 })
                    if key.isEmpty {
                        throw TestError.emptyPrivateKey
                    }
                    return key
                }),
                format: .der
            )
        ) { reloader in
            // On first attempt, the overrides should be correctly present.
            var override = reloader.sslContextConfigurationOverride
            XCTAssertEqual(
                override.certificateChain,
                [.certificate(try .init(bytes: Self.sampleCert.serializeAsPEM().derBytes, format: .der))]
            )
            XCTAssertEqual(
                override.privateKey,
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey.derRepresentation), format: .der))
            )

            // Update the box to contain empty bytes: this will cause the provider to throw.
            keyBox.withLockedValue({ $0 = [] })

            // Give the reload loop some time to run and update the cert-key pair.
            try await Task.sleep(for: .milliseconds(100), tolerance: .zero)

            // We should still be offering the previously valid cert-key pair.
            override = reloader.sslContextConfigurationOverride
            XCTAssertEqual(
                override.certificateChain,
                [.certificate(try .init(bytes: Self.sampleCert.serializeAsPEM().derBytes, format: .der))]
            )
            XCTAssertEqual(
                override.privateKey,
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey.derRepresentation), format: .der))
            )
        }
    }

    func testCertificateAndKeyDoNotMatchOnReload() async throws {
        let keyBox: NIOLockedValueBox<[UInt8]> = NIOLockedValueBox(
            Array(Self.samplePrivateKey.derRepresentation)
        )
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { try Self.sampleCert.serializeAsPEM().derBytes }),
                format: .der
            ),
            privateKey: .init(
                location: .memory(provider: { keyBox.withLockedValue({ $0 }) }),
                format: .der
            )
        ) { reloader in
            // On first attempt, the overrides should be correctly present.
            var override = reloader.sslContextConfigurationOverride
            XCTAssertEqual(
                override.certificateChain,
                [.certificate(try .init(bytes: Self.sampleCert.serializeAsPEM().derBytes, format: .der))]
            )
            XCTAssertEqual(
                override.privateKey,
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey.derRepresentation), format: .der))
            )

            // Update the box to contain a key that does not match the given certificate.
            keyBox.withLockedValue({ $0 = Array(P384.Signing.PrivateKey().derRepresentation) })

            // Give the reload loop some time to run and update the cert-key pair.
            try await Task.sleep(for: .milliseconds(100), tolerance: .zero)

            // We should still be offering the previously valid cert-key pair.
            override = reloader.sslContextConfigurationOverride
            XCTAssertEqual(
                override.certificateChain,
                [.certificate(try .init(bytes: Self.sampleCert.serializeAsPEM().derBytes, format: .der))]
            )
            XCTAssertEqual(
                override.privateKey,
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey.derRepresentation), format: .der))
            )
        }
    }

    func testCertificateReloaderErrorDescription() {
        XCTAssertEqual(
            "\(TLSConfiguration.CertificateReloaderError.missingCertificateChain)",
            "Missing certificate chain"
        )
        XCTAssertEqual(
            "\(TLSConfiguration.CertificateReloaderError.missingPrivateKey)",
            "Missing private key"
        )
    }

    func testTimedCertificateReloaderErrorDescription() {
        XCTAssertEqual(
            "\(TimedCertificateReloader.Error.certificatePathNotFound("some/path"))",
            "Certificate path not found: some/path"
        )
        XCTAssertEqual(
            "\(TimedCertificateReloader.Error.privateKeyPathNotFound("some/path"))",
            "Private key path not found: some/path"
        )
    }

    static let startDate = Date()
    static let samplePrivateKey = P384.Signing.PrivateKey()
    static let sampleCertName = try! DistinguishedName {
        CountryName("US")
        OrganizationName("Apple")
        CommonName("Swift Certificate Test")
    }
    static let sampleCert: Certificate = {
        try! Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: .init(samplePrivateKey.publicKey),
            notValidBefore: startDate.advanced(by: -60 * 60 * 24 * 360),
            notValidAfter: startDate.advanced(by: 60 * 60 * 24 * 360),
            issuer: sampleCertName,
            subject: sampleCertName,
            signatureAlgorithm: .ecdsaWithSHA384,
            extensions: Certificate.Extensions {
                Critical(
                    BasicConstraints.isCertificateAuthority(maxPathLength: nil)
                )
            },
            issuerPrivateKey: .init(samplePrivateKey)
        )
    }()

    private func runTimedCertificateReloaderTest(
        certificate: TimedCertificateReloader.CertificateSource,
        privateKey: TimedCertificateReloader.PrivateKeySource,
        validateSources: Bool = true,
        _ body: @escaping @Sendable (TimedCertificateReloader) async throws -> Void
    ) async throws {
        let reloader = TimedCertificateReloader(
            refreshInterval: .milliseconds(50),
            certificateSource: .init(
                location: certificate.location,
                format: certificate.format
            ),
            privateKeySource: .init(location: privateKey.location, format: privateKey.format)
        )

        if validateSources {
            try reloader.reload()
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await reloader.run()
            }
            try await body(reloader)
            group.cancelAll()
        }
    }
}
