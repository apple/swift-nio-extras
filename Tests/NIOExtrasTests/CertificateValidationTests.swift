//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Crypto
import Foundation
import Logging
import NIOConcurrencyHelpers
import NIOExtras
import NIOSSL
import SwiftASN1
import Synchronization
import Testing
import X509

struct CertificateValidationTests {
    @Test
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
    func testValidateNIOSSLCertificatesHappyPath() async throws {
        final class RecorderPolicy: VerifierPolicy, Sendable {
            let lastSeenChain: NIOLockedValueBox<UnverifiedCertificateChain?> = .init(nil)

            let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = []

            init() {}

            func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
                self.lastSeenChain.withLockedValue { $0 = chain }
                return .meetsPolicy
            }
        }
        let policy = RecorderPolicy()

        let testChain = try TestCertificates.makeSelfSigned()
        var verifier = Verifier(rootCertificates: .init([testChain.ca])) {
            policy
        }
        let nioChain = try testChain.fullChain.map { try NIOSSLCertificate($0) }

        let result = await verifier.validate(chain: nioChain, diagnosticCallback: { print("\($0)") })
        #expect(result == .certificateVerified)
        policy.lastSeenChain.withLockedValue { lastSeenChain in
            #expect(lastSeenChain?.leaf == .init(testChain.leaf))
        }
    }

    @Test
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
    func testValidateNIOSSLCertificatesFails() async throws {
        final class RecorderPolicy: VerifierPolicy, Sendable {
            let lastSeenChain: NIOLockedValueBox<UnverifiedCertificateChain?> = .init(nil)

            let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = []

            init() {}

            func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
                self.lastSeenChain.withLockedValue { $0 = chain }
                return .failsToMeetPolicy(reason: "some test error")
            }
        }
        let policy = RecorderPolicy()

        let testChain = try TestCertificates.makeSelfSigned()
        var verifier = Verifier(rootCertificates: .init([testChain.ca])) {
            policy
        }
        let nioChain = try testChain.fullChain.map { try NIOSSLCertificate($0) }

        let result = await verifier.validate(chain: nioChain, diagnosticCallback: nil)
        #expect(result == .failed)
        policy.lastSeenChain.withLockedValue { lastSeenChain in
            #expect(lastSeenChain?.leaf == .init(testChain.leaf))
        }
    }

    @Test
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
    func testValidateEmptyChain() async {
        final class RecorderPolicy: VerifierPolicy, Sendable {
            let lastSeenChain: NIOLockedValueBox<UnverifiedCertificateChain?> = .init(nil)

            let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = []

            init() {}

            func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
                self.lastSeenChain.withLockedValue { $0 = chain }
                return .failsToMeetPolicy(reason: "some test error")
            }
        }
        let policy = RecorderPolicy()

        var verifier = Verifier(rootCertificates: .init([])) {
            policy
        }

        let result = await verifier.validate(chain: [], diagnosticCallback: nil)
        #expect(result == .failed)
        policy.lastSeenChain.withLockedValue { lastSeenChain in
            #expect(lastSeenChain == nil)  // We don't get as far as the policy
        }
    }
}

private struct TestCertificate {
    let leaf: Certificate
    let ca: Certificate
    let privateKey: P384.Signing.PrivateKey

    var fullChain: [Certificate] {
        [self.leaf, self.ca]
    }
}

enum TestCertificates {
    fileprivate static func makeSelfSigned() throws -> TestCertificate {
        let key = P384.Signing.PrivateKey()

        let caName = try DistinguishedName {
            CommonName("some ca")
        }
        let leafName = try DistinguishedName {
            CommonName("localhost")
        }
        let ca = try make(
            issuerName: caName,
            issuerKey: .init(key),
            publicKey: .init(key.publicKey),
            subject: caName,
            extensions: .init {
                BasicConstraints.isCertificateAuthority(maxPathLength: nil)
            }
        )
        let leaf = try make(
            issuerName: caName,
            issuerKey: .init(key),
            publicKey: .init(key.publicKey),
            subject: leafName,
            extensions: .init()
        )
        return .init(leaf: leaf, ca: ca, privateKey: key)
    }

    private static func make(
        issuerName: DistinguishedName,
        issuerKey: Certificate.PrivateKey,
        publicKey: Certificate.PublicKey,
        subject: DistinguishedName,
        extensions: Certificate.Extensions
    ) throws -> Certificate {
        let now = Date.now
        let certificate = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: publicKey,
            notValidBefore: now.addingTimeInterval(-60),
            notValidAfter: now.addingTimeInterval(60),  // 60 seconds from now
            issuer: issuerName,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA384,
            extensions: extensions,
            issuerPrivateKey: issuerKey
        )
        return certificate
    }
}

extension NIOSSLCertificate {
    fileprivate convenience init(_ cert: Certificate) throws {
        try self.init(bytes: cert.serializeAsPEM().derBytes, format: .der)
    }
}
