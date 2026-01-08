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

import Foundation
import NIOSSL
import SwiftASN1
import X509

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Certificate {
    fileprivate init(_ certificate: NIOSSLCertificate) throws {
        try self.init(derEncoded: certificate.toDERBytes())
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension NIOSSLCertificate {
    fileprivate convenience init(_ cert: Certificate) throws {
        try self.init(bytes: cert.serializeAsPEM().derBytes, format: .der)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
extension Verifier {
    /// This function bridges NIOSSL into swift-certificates. It means we can use a VerifierPolicy as a NIOSSL callback
    public mutating func validate(
        chain: [NIOSSLCertificate],
        diagnosticCallback: ((VerificationDiagnostic) -> Void)?
    ) async -> NIOSSLVerificationResultWithMetadata {
        guard let nioLeaf = chain.first else {
            return .failed
        }
        let x509Chain: [Certificate]
        let x509Leaf: Certificate
        do {
            // This would only throw if the certificate from NIOSSLCertificate.toDERBytes was not parseable by Certificate.init(derEncoded:), or if toDERBytes failed to convert to bytes.
            x509Chain = try chain[1...].map { try X509.Certificate($0) }
            x509Leaf = try X509.Certificate(nioLeaf)
        } catch {
            return .failed
        }

        let result = await self.validate(
            leafCertificate: x509Leaf,
            intermediates: .init(x509Chain),
            diagnosticCallback: diagnosticCallback
        )
        switch result {
        case .validCertificate(let validatedChain):
            do {
                // This won't throw in practise
                let validatedNioChain = try validatedChain.map { try NIOSSLCertificate($0) }
                let metadata = VerificationMetadata(ValidatedCertificateChain(validatedNioChain))
                return .certificateVerified(metadata)
            } catch {
                return .failed
            }
        case .couldNotValidate:
            return .failed
        }
    }
}
