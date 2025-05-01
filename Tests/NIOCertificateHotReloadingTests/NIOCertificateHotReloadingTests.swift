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
import NIOCertificateHotReloading
import NIOConcurrencyHelpers
import X509
import XCTest

final class TimedCertificateReloaderTests: XCTestCase {
    func testCertificatePathDoesNotExist() async throws {
        try await runTimedCertificateReloaderTest(
            certificate: .init(location: .file(path: "doesnotexist"), format: .der),
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

    func testKeyPathDoesNotExist() async throws {
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { try? Self.sampleCert.serializeAsPEM().derBytes }),
                format: .der
            ),
            privateKey: .init(
                location: .file(path: "doesnotexist"),
                format: .der
            )
        ) { reloader in
            let override = reloader.sslContextConfigurationOverride
            XCTAssertNil(override.certificateChain)
            XCTAssertNil(override.privateKey)
        }
    }

    func testCertificateIsInUnexpectedFormat() async throws {
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { try? Self.sampleCert.serializeAsPEM().derBytes }),
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

    func testKeyIsInUnexpectedFormat() async throws {
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { try? Self.sampleCert.serializeAsPEM().derBytes }),
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

    func testCertificateAndKeyDoNotMatch() async throws {
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { try? Self.sampleCert.serializeAsPEM().derBytes }),
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

    func testReloadSuccessfully() async throws {
        let certificateBox: NIOLockedValueBox<[UInt8]?> = NIOLockedValueBox(nil)
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { certificateBox.withLockedValue({ $0 }) }),
                format: .der
            ),
            privateKey: .init(
                location: .memory(provider: { Array(Self.samplePrivateKey.derRepresentation) }),
                format: .der
            )
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

    func testCertificateNotFoundAtReload() async throws {
        let certificateBox: NIOLockedValueBox<[UInt8]?> = NIOLockedValueBox(
            try! Self.sampleCert.serializeAsPEM().derBytes
        )
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { certificateBox.withLockedValue({ $0 }) }),
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

            // Update the box to not contain a certificate.
            certificateBox.withLockedValue({ $0 = nil })

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
        let keyBox: NIOLockedValueBox<[UInt8]?> = NIOLockedValueBox(
            Array(Self.samplePrivateKey.derRepresentation)
        )
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { try! Self.sampleCert.serializeAsPEM().derBytes }),
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

            // Update the box to not contain a key.
            keyBox.withLockedValue({ $0 = nil })

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
        let keyBox: NIOLockedValueBox<[UInt8]?> = NIOLockedValueBox(
            Array(Self.samplePrivateKey.derRepresentation)
        )
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { try! Self.sampleCert.serializeAsPEM().derBytes }),
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
        certificate: TimedCertificateReloader.CertificateDescription,
        privateKey: TimedCertificateReloader.PrivateKeyDescription,
        _ body: @escaping @Sendable (TimedCertificateReloader) async throws -> Void
    ) async throws {
        let reloader = TimedCertificateReloader(
            refreshInterval: .milliseconds(50),
            certificateDescription: .init(
                location: certificate.location,
                format: certificate.format
            ),
            privateKeyDescription: .init(location: privateKey.location, format: privateKey.format)
        )
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await reloader.run()
            }
            group.addTask {
                try await body(reloader)
            }
            try await group.next()
            group.cancelAll()
        }
    }
}
