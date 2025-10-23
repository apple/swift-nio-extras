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
        let failureBox = NIOLockedValueBox([TimedCertificateReloader.CertificateChainAndKeyPairReloadFailure]())
        try await runTimedCertificateReloaderTest(
            certificate: .init(location: .file(path: "doesnotexist"), format: .der),
            privateKey: .init(
                location: .memory(provider: { Array(Self.samplePrivateKey1.derRepresentation) }),
                format: .der
            ),
            validateSources: false,
            onLoadFailed: { failure in
                failureBox.withLockedValue { $0.append(failure) }
            },
            { reloader in
                let override = reloader.sslContextConfigurationOverride
                XCTAssertNil(override.certificateChain)
                XCTAssertNil(override.privateKey)
                XCTAssertEqual(failureBox.withLockedValue { $0 }.count, 0)
                let result = Result { try reloader.reload() }
                XCTAssertEqual(failureBox.withLockedValue { $0 }.count, 1)
                XCTAssertThrowsError(try result.get())
            }
        )
    }

    func testCertificatePathDoesNotExist_ValidatingSource() async throws {
        let failureBox = NIOLockedValueBox([TimedCertificateReloader.CertificateChainAndKeyPairReloadFailure]())
        do {
            try await runTimedCertificateReloaderTest(
                certificate: .init(location: .file(path: "doesnotexist"), format: .der),
                privateKey: .init(
                    location: .memory(provider: { Array(Self.samplePrivateKey1.derRepresentation) }),
                    format: .der
                ),
                onLoadFailed: { failure in
                    failureBox.withLockedValue { $0.append(failure) }
                },
                { _ in
                    XCTFail("Test should have failed before reaching this point.")
                }
            )
        } catch {
            guard let errorFromCallback = failureBox.withLockedValue({ $0 }).first else {
                XCTFail("No error from callback")
                return
            }
            XCTAssertEqual(
                error as? TimedCertificateReloader.Error,
                TimedCertificateReloader.Error.certificatePathNotFound("doesnotexist")
            )
            XCTAssertEqual(
                error as? TimedCertificateReloader.Error,
                errorFromCallback.error as? TimedCertificateReloader.Error
            )
        }
    }

    func testNonSelfSignedCert() async throws {
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .memory(provider: { try Self.sampleCertNotSelfSigned.serializeAsPEM().derBytes }),
                format: .der
            ),
            privateKey: .init(
                location: .memory(provider: { Array(Self.samplePrivateKey1.derRepresentation) }),
                format: .der
            ),
            validateSources: true
        ) { reloader in
            let override = reloader.sslContextConfigurationOverride
            XCTAssertNotNil(override.certificateChain)
            XCTAssertNotNil(override.privateKey)
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
        do {
            try await runTimedCertificateReloaderTest(
                certificate: .init(
                    location: .memory(provider: { try Self.sampleCert.serializeAsPEM().derBytes }),
                    format: .pem
                ),
                privateKey: .init(
                    location: .memory(provider: { Array(Self.samplePrivateKey1.derRepresentation) }),
                    format: .der
                )
            ) { reloader in
                XCTFail("Certificate reloader loaded correctly.")
            }
        } catch let error as TimedCertificateReloader.Error {
            XCTAssert(error == .certificateLoadingError(reason: "Certificate data is not valid UTF-8."))
        } catch {
            XCTFail("Encountered unexpected error \(error)")
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

        do {
            try await runTimedCertificateReloaderTest(
                certificate: .init(
                    location: .file(path: file.path),
                    format: .pem
                ),
                privateKey: .init(
                    location: .memory(provider: { Array(Self.samplePrivateKey1.derRepresentation) }),
                    format: .der
                )
            ) { reloader in
                XCTFail("Certificate reloader loaded correctly.")
            }
        } catch let error as TimedCertificateReloader.Error {
            XCTAssert(error == .certificateLoadingError(reason: "Certificate data is not valid UTF-8."))
        } catch {
            XCTFail("Encountered unexpected error \(error)")
        }
    }

    func testKeyIsInUnexpectedFormat_FromMemory() async throws {
        do {
            try await runTimedCertificateReloaderTest(
                certificate: .init(
                    location: .memory(provider: { try Self.sampleCert.serializeAsPEM().derBytes }),
                    format: .der
                ),
                privateKey: .init(
                    location: .memory(provider: { Array(Self.samplePrivateKey1.derRepresentation) }),
                    format: .pem
                )
            ) { reloader in
                XCTFail("Certificate reloader loaded correctly.")
            }
        } catch let error as TimedCertificateReloader.Error {
            XCTAssert(error == .privateKeyLoadingError(reason: "Private Key data is not valid UTF-8."))
        } catch {
            XCTFail("Encountered unexpected error \(error)")
        }
    }

    func testKeyIsInUnexpectedFormat_FromFile() async throws {
        let keyBytes = Self.samplePrivateKey1.derRepresentation
        let file = try self.createTempFile(contents: keyBytes)

        do {
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
                XCTFail("Certificate reloader loaded correctly.")
            }
        } catch let error as TimedCertificateReloader.Error {
            XCTAssert(error == .privateKeyLoadingError(reason: "Private Key data is not valid UTF-8."))
        } catch {
            XCTFail("Encountered unexpected error \(error)")
        }
    }

    func testCertificateAndKeyDoNotMatch() async throws {
        do {
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
                XCTFail("Certificate reloader loaded correctly.")
            }
        } catch let error as TimedCertificateReloader.Error {
            XCTAssert(error == .publicKeyMismatch)
        } catch {
            XCTFail("Encountered unexpected error \(error)")
        }
    }

    func testEmptyCertificateChain() async throws {
        do {
            try await runTimedCertificateReloaderTest(
                certificate: .init(
                    location: .memory(provider: { [] }),
                    format: .pem
                ),
                privateKey: .init(
                    location: .memory(provider: { Array(Self.samplePrivateKey1.derRepresentation) }),
                    format: .der
                )
            ) { reloader in
                XCTFail("Certificate reloader loaded correctly.")
            }
        } catch let error as TimedCertificateReloader.Error {
            XCTAssert(error == .certificateLoadingError(reason: "The provided file does not contain any certificates."))
        } catch {
            XCTFail("Encountered unexpected error \(error)")
        }
    }

    enum TestError: Error {
        case emptyCertificate
        case emptyPrivateKey
        case couldNotCreateFile
    }

    func testReloadSuccessfully_FromMemory() async throws {
        let certificateBox: NIOLockedValueBox<[UInt8]> = NIOLockedValueBox([])
        let updatesBox = NIOLockedValueBox([TimedCertificateReloader.CertificateChainAndKeyPairReloadDiff]())
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
                location: .memory(provider: { Array(Self.samplePrivateKey1.derRepresentation) }),
                format: .der
            ),
            // We need to disable validation because the provider will initially be empty.
            validateSources: false,
            onLoaded: { info in
                updatesBox.withLockedValue { $0.append(info) }
            },
            { reloader in
                // On first attempt, we should have no certificate or private key overrides available,
                // since the certificate box is empty.
                var override = reloader.sslContextConfigurationOverride
                XCTAssertNil(override.certificateChain)
                XCTAssertNil(override.privateKey)
                XCTAssertEqual(updatesBox.withLockedValue { $0.count }, 0)

                // Update the box to contain a valid certificate.
                certificateBox.withLockedValue({ $0 = try! Self.sampleCert.serializeAsPEM().derBytes })

                // Give the reload loop some time to run and update the cert-key pair.
                try await Task.sleep(for: .milliseconds(200), tolerance: .zero)
                // We reload every 50ms and slept 200. There should be 1 reload which has nil previous certs and at least 1 which does not.
                let updates = updatesBox.withLockedValue { $0 }
                XCTAssertGreaterThanOrEqual(updates.count, 2)
                XCTAssertNil(updates.first?.previousCertificateChain)
                XCTAssertNil(updates.first?.previousPrivateKey)
                for update in updates.dropFirst() {
                    XCTAssertEqual(update.previousCertificateChain, update.currentCertificateChain)
                    XCTAssertEqual(update.previousX509CertificateChain, update.currentX509CertificateChain)
                    XCTAssertEqual(update.previousPrivateKey, update.currentPrivateKey)
                    XCTAssertEqual(update.previousX509PrivateKey, update.currentX509PrivateKey)
                }
                for updateInfo in updates {
                    XCTAssertEqual(updateInfo.currentCertificateChain.count, 1)
                    XCTAssertEqual(
                        updateInfo.currentCertificateChain,
                        reloader.sslContextConfigurationOverride.certificateChain
                    )
                    XCTAssertEqual(updateInfo.currentX509CertificateChain.first, Self.sampleCert)
                    XCTAssertEqual(updateInfo.currentPrivateKey, reloader.sslContextConfigurationOverride.privateKey)
                    XCTAssertEqual(updateInfo.currentX509PrivateKey, .init(Self.samplePrivateKey1))
                }

                // Now the overrides should be present.
                override = reloader.sslContextConfigurationOverride
                XCTAssertEqual(
                    override.certificateChain,
                    [.certificate(try .init(bytes: Self.sampleCert.serializeAsPEM().derBytes, format: .der))]
                )
                XCTAssertEqual(
                    override.privateKey,
                    .privateKey(try .init(bytes: Array(Self.samplePrivateKey1.derRepresentation), format: .der))
                )
            }
        )
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
            try Self.samplePrivateKey1.derRepresentation.write(to: privateKeyFile)

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
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey1.derRepresentation), format: .der))
            )
        }
    }

    func testReloadSuccessfullyCertificateChain_FromMemory() async throws {
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
                format: .pem
            ),
            privateKey: .init(
                location: .memory(provider: { Array(Self.samplePrivateKey1.derRepresentation) }),
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
            certificateBox.withLockedValue({
                $0 = Array(
                    try! Self.sampleCertChain.map { try $0.serializeAsPEM().pemString }.joined(separator: "\n").utf8
                )
            })

            // Give the reload loop some time to run and update the cert-key pair.
            try await Task.sleep(for: .milliseconds(100), tolerance: .zero)

            // Now the overrides should be present.
            override = reloader.sslContextConfigurationOverride
            XCTAssertEqual(
                override.certificateChain,
                try Self.sampleCertChain.map {
                    .certificate(try .init(bytes: $0.serializeAsPEM().derBytes, format: .der))
                }
            )
            XCTAssertEqual(
                override.privateKey,
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey1.derRepresentation), format: .der))
            )
        }
    }

    func testReloadSuccessfullyCertificateChain_FromFile() async throws {
        // Start with empty files.
        let certificateFile = try self.createTempFile(contents: Data())
        let privateKeyFile = try self.createTempFile(contents: Data())
        try await runTimedCertificateReloaderTest(
            certificate: .init(
                location: .file(path: certificateFile.path),
                format: .pem
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
            try Data(try Self.sampleCertChain.map { try $0.serializeAsPEM().pemString }.joined(separator: "\n").utf8)
                .write(to: certificateFile)
            try Self.samplePrivateKey1.derRepresentation.write(to: privateKeyFile)

            // Give the reload loop some time to run and update the cert-key pair.
            try await Task.sleep(for: .milliseconds(100), tolerance: .zero)

            // Now the overrides should be present.
            override = reloader.sslContextConfigurationOverride
            XCTAssertEqual(
                override.certificateChain,
                try Self.sampleCertChain.map {
                    .certificate(try .init(bytes: $0.serializeAsPEM().derBytes, format: .der))
                }
            )
            XCTAssertEqual(
                override.privateKey,
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey1.derRepresentation), format: .der))
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
                location: .memory(provider: { Array(Self.samplePrivateKey1.derRepresentation) }),
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
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey1.derRepresentation), format: .der))
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
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey1.derRepresentation), format: .der))
            )
        }
    }

    func testKeyNotFoundAtReload() async throws {
        let keyBox: NIOLockedValueBox<[UInt8]> = NIOLockedValueBox(
            Array(Self.samplePrivateKey1.derRepresentation)
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
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey1.derRepresentation), format: .der))
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
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey1.derRepresentation), format: .der))
            )
        }
    }

    func testCertificateAndKeyDoNotMatchOnReload() async throws {
        let keyBox: NIOLockedValueBox<[UInt8]> = NIOLockedValueBox(
            Array(Self.samplePrivateKey1.derRepresentation)
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
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey1.derRepresentation), format: .der))
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
                .privateKey(try .init(bytes: Array(Self.samplePrivateKey1.derRepresentation), format: .der))
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

    /// This tests the first makeReloaderValidatingSources helper function, which takes many parameters.
    func testCreateValidating() throws {
        let reloader = try TimedCertificateReloader.makeReloaderValidatingSources(
            refreshInterval: .milliseconds(50),
            certificateSource: .init(
                location: .memory(provider: { try Self.sampleCert.serializeAsPEM().derBytes }),
                format: .der
            ),
            privateKeySource: .init(
                location: .memory(provider: { Array(Self.samplePrivateKey1.derRepresentation) }),
                format: .der
            )
        )
        // Cert should have been loaded once already
        XCTAssertEqual(
            reloader.sslContextConfigurationOverride.certificateChain,
            [.certificate(try .init(bytes: Self.sampleCert.serializeAsPEM().derBytes, format: .der))]
        )
        XCTAssertEqual(
            reloader.sslContextConfigurationOverride.privateKey,
            .privateKey(try .init(bytes: Array(Self.samplePrivateKey1.derRepresentation), format: .der))
        )
    }

    /// This tests the other makeReloaderValidatingSources helper function, which takes a configuration.
    func testCreateValidatingConfig() throws {
        let config = TimedCertificateReloader.Configuration(
            refreshInterval: .milliseconds(50),
            certificateSource: .init(
                location: .memory(provider: { try Self.sampleCert.serializeAsPEM().derBytes }),
                format: .der
            ),
            privateKeySource: .init(
                location: .memory(provider: { Array(Self.samplePrivateKey1.derRepresentation) }),
                format: .der
            )
        )
        let reloader = try TimedCertificateReloader.makeReloaderValidatingSources(configuration: config)
        // Cert should have been loaded once already
        XCTAssertEqual(
            reloader.sslContextConfigurationOverride.certificateChain,
            [.certificate(try .init(bytes: Self.sampleCert.serializeAsPEM().derBytes, format: .der))]
        )
        XCTAssertEqual(
            reloader.sslContextConfigurationOverride.privateKey,
            .privateKey(try .init(bytes: Array(Self.samplePrivateKey1.derRepresentation), format: .der))
        )
    }

    /// This tests makeReloaderValidatingSources when the sources are not valid.
    func testCreateValidatingConfigInvalid() throws {
        let config = TimedCertificateReloader.Configuration(
            refreshInterval: .milliseconds(50),
            certificateSource: .init(
                location: .memory(provider: { Array() }),
                format: .der
            ),
            privateKeySource: .init(
                location: .memory(provider: { Array() }),
                format: .der
            )
        )
        XCTAssertThrowsError(try TimedCertificateReloader.makeReloaderValidatingSources(configuration: config))
    }

    /// This tests that `makeServerConfigurationWithMTLS(certificateReloader:trustRoots:)` correctly extracts the
    /// certificate chain and private key from `certificateReloader` and sets those in the returned `TLSConfiguration`
    /// (along with `trustRoots` and setting `.certificateVerification` to `.noHostnameVerification`)
    func testCreateServerConfigWithMTLS() async throws {
        let certificateReloader = try TimedCertificateReloader.makeReloaderValidatingSources(
            refreshInterval: .seconds(10),
            certificateSource: .init(
                location: .memory(provider: {
                    .init(
                        try Self.sampleCertChain.map { try $0.serializeAsPEM().pemString }.joined(separator: "\n").utf8
                    )
                }),
                format: .pem
            ),
            privateKeySource: .init(
                location: .memory(provider: { .init(Self.samplePrivateKey1.derRepresentation) }),
                format: .der
            )
        )

        let trustRoots = NIOSSLTrustRoots.certificates(
            try Self.sampleCertChain.map {
                try NIOSSLCertificate(bytes: .init($0.serializeAsPEM().pemString.utf8), format: .pem)
            }
        )

        let tlsConfiguration = try TLSConfiguration.makeServerConfigurationWithMTLS(
            certificateReloader: certificateReloader,
            trustRoots: trustRoots
        )

        // Check whether the configuration is set up with the same certificate chain, private key, and trust roots
        // that were used to initialize the reloader
        XCTAssertEqual(
            tlsConfiguration.certificateChain,
            try Self.sampleCertChain.map {
                .certificate(try NIOSSLCertificate(bytes: $0.serializeAsPEM().derBytes, format: .der))
            }
        )
        XCTAssertEqual(
            tlsConfiguration.privateKey,
            NIOSSLPrivateKeySource.privateKey(
                try NIOSSLPrivateKey(bytes: .init(Self.samplePrivateKey1.derRepresentation), format: .der)
            )
        )
        XCTAssertEqual(tlsConfiguration.trustRoots, trustRoots)

        XCTAssertEqual(tlsConfiguration.certificateVerification, .noHostnameVerification)
    }

    static let startDate = Date()
    static let samplePrivateKey1 = P384.Signing.PrivateKey()
    static let samplePrivateKey2 = P384.Signing.PrivateKey()
    static let sampleCertName = try! DistinguishedName {
        CountryName("US")
        OrganizationName("Apple")
        CommonName("Swift Certificate Test")
    }
    static let issuerCertName = try! DistinguishedName {
        CountryName("US")
        OrganizationName("Apple")
        CommonName("Swift Certificate Test Issuer")
    }
    static let sampleCert: Certificate = {
        try! Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: .init(samplePrivateKey1.publicKey),
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
            issuerPrivateKey: .init(samplePrivateKey1)
        )
    }()
    static let sampleCertNotSelfSigned: Certificate = {
        try! Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: .init(samplePrivateKey1.publicKey),
            notValidBefore: startDate.advanced(by: -60 * 60 * 24 * 360),
            notValidAfter: startDate.advanced(by: 60 * 60 * 24 * 360),
            issuer: issuerCertName,
            subject: sampleCertName,
            signatureAlgorithm: .ecdsaWithSHA384,
            extensions: Certificate.Extensions {
                Critical(
                    BasicConstraints.isCertificateAuthority(maxPathLength: nil)
                )
            },
            issuerPrivateKey: .init(samplePrivateKey2)
        )
    }()
    static let sampleCertChain: [Certificate] = {
        [
            try! Certificate(
                version: .v3,
                serialNumber: .init(),
                publicKey: .init(samplePrivateKey1.publicKey),
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
                issuerPrivateKey: .init(samplePrivateKey1)
            ),
            try! Certificate(
                version: .v3,
                serialNumber: .init(),
                publicKey: .init(samplePrivateKey2.publicKey),
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
                issuerPrivateKey: .init(samplePrivateKey2)
            ),
        ]
    }()

    private func runTimedCertificateReloaderTest(
        certificate: TimedCertificateReloader.CertificateSource,
        privateKey: TimedCertificateReloader.PrivateKeySource,
        validateSources: Bool = true,
        onLoaded: (@Sendable (TimedCertificateReloader.CertificateChainAndKeyPairReloadDiff) -> Void)? = nil,
        onLoadFailed: (@Sendable (TimedCertificateReloader.CertificateChainAndKeyPairReloadFailure) -> Void)? = nil,
        _ body: @escaping @Sendable (TimedCertificateReloader) async throws -> Void
    ) async throws {
        let config = TimedCertificateReloader.Configuration(
            refreshInterval: .milliseconds(50),
            certificateSource: .init(
                location: certificate.location,
                format: certificate.format
            ),
            privateKeySource: .init(location: privateKey.location, format: privateKey.format)
        ) {
            $0.onCertificateLoaded = onLoaded
            $0.onCertificateLoadFailed = onLoadFailed
        }
        let reloader = TimedCertificateReloader(configuration: config)

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
