//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import HTTPTypes
import StructuredFieldValues

/// Implements `draft-ietf-httpbis-resumable-upload-01` internet-draft.
///
/// Draft document:
/// https://datatracker.ietf.org/doc/draft-ietf-httpbis-resumable-upload/01/
enum HTTPResumableUploadProtocol {
    enum InteropVersion: Int, Comparable {
        case v3 = 3
        case v5 = 5
        case v6 = 6

        static let latest: Self = .v6

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    static func featureDetectionResponse(
        resumePath: String,
        in context: HTTPResumableUploadContext,
        version: InteropVersion
    ) -> HTTPResponse {
        var response = HTTPResponse(status: .init(code: 104, reasonPhrase: "Upload Resumption Supported"))
        response.headerFields[.uploadDraftInteropVersion] = "\(version.rawValue)"
        response.headerFields[.location] = context.origin + resumePath
        return response
    }

    static func offsetRetrievingResponse(offset: Int64, complete: Bool, version: InteropVersion) -> HTTPResponse {
        var response = HTTPResponse(status: .noContent)
        response.headerFields[.uploadDraftInteropVersion] = "\(version.rawValue)"
        if version >= .v5 {
            response.headerFields.uploadComplete = complete
        } else {
            response.headerFields.uploadIncomplete = !complete
        }
        response.headerFields.uploadOffset = offset
        response.headerFields[.cacheControl] = "no-store"
        return response
    }

    static func incompleteResponse(
        offset: Int64,
        resumePath: String,
        forUploadCreation: Bool,
        in context: HTTPResumableUploadContext,
        version: InteropVersion
    ) -> HTTPResponse {
        var response = HTTPResponse(status: .created)
        response.headerFields[.uploadDraftInteropVersion] = "\(version.rawValue)"
        if forUploadCreation {
            response.headerFields[.location] = context.origin + resumePath
        }
        if version >= .v5 {
            response.headerFields.uploadComplete = false
        } else {
            response.headerFields.uploadIncomplete = true
        }
        response.headerFields.uploadOffset = offset
        return response
    }

    static func optionsResponse(version: InteropVersion) -> HTTPResponse {
        var response = HTTPResponse(status: .ok)
        response.headerFields[.uploadDraftInteropVersion] = "\(version.rawValue)"
        response.headerFields.uploadLimit = .init(minSize: 0)
        return response
    }

    static func cancelledResponse(version: InteropVersion) -> HTTPResponse {
        var response = HTTPResponse(status: .noContent)
        response.headerFields[.uploadDraftInteropVersion] = "\(version.rawValue)"
        return response
    }

    static func notFoundResponse(version: InteropVersion) -> HTTPResponse {
        var response = HTTPResponse(status: .notFound)
        response.headerFields[.uploadDraftInteropVersion] = "\(version.rawValue)"
        response.headerFields[.contentLength] = "0"
        return response
    }

    static func conflictResponse(offset: Int64, complete: Bool, version: InteropVersion) -> HTTPResponse {
        var response = HTTPResponse(status: .conflict)
        response.headerFields[.uploadDraftInteropVersion] = "\(version.rawValue)"
        if version >= .v5 {
            response.headerFields.uploadComplete = complete
        } else {
            response.headerFields.uploadIncomplete = !complete
        }
        response.headerFields.uploadOffset = offset
        response.headerFields[.contentLength] = "0"
        return response
    }

    static func badRequestResponse() -> HTTPResponse {
        var response = HTTPResponse(status: .badRequest)
        response.headerFields[.uploadDraftInteropVersion] = "\(InteropVersion.latest.rawValue)"
        response.headerFields[.contentLength] = "0"
        return response
    }

    enum RequestType {
        case uploadCreation(complete: Bool, contentLength: Int64?, uploadLength: Int64?)
        case offsetRetrieving
        case uploadAppending(offset: Int64, complete: Bool, contentLength: Int64?, uploadLength: Int64?)
        case uploadCancellation
        case options
    }

    enum InvalidRequestError: Error {
        case unsupportedInteropVersion
        case unknownMethod
        case invalidPath
        case missingHeaderField
        case extraHeaderField
    }

    static func identifyRequest(
        _ request: HTTPRequest,
        in context: HTTPResumableUploadContext
    ) throws -> (RequestType, InteropVersion)? {
        guard let versionValue = request.headerFields[.uploadDraftInteropVersion] else {
            return nil
        }
        guard let versionNumber = Int(versionValue),
            let version = InteropVersion(rawValue: versionNumber)
        else {
            throw InvalidRequestError.unsupportedInteropVersion
        }
        let complete: Bool?
        if version >= .v5 {
            complete = request.headerFields.uploadComplete
        } else {
            complete = request.headerFields.uploadIncomplete.map { !$0 }
        }
        let offset = request.headerFields.uploadOffset
        let contentLength = request.headerFields[.contentLength].flatMap(Int64.init)
        let uploadLength = request.headerFields.uploadLength
        if request.method == .options {
            guard complete == nil && offset == nil && uploadLength == nil else {
                throw InvalidRequestError.extraHeaderField
            }
            return (.options, version)
        }
        if let path = request.path, context.isResumption(path: path) {
            switch request.method {
            case .head:
                guard complete == nil && offset == nil && uploadLength == nil else {
                    throw InvalidRequestError.extraHeaderField
                }
                return (.offsetRetrieving, version)
            case .patch:
                guard let offset else {
                    throw InvalidRequestError.missingHeaderField
                }
                if version >= .v6 && request.headerFields[.contentType] != "application/partial-upload" {
                    throw InvalidRequestError.missingHeaderField
                }
                return (
                    .uploadAppending(
                        offset: offset,
                        complete: complete ?? true,
                        contentLength: contentLength,
                        uploadLength: uploadLength
                    ), version
                )
            case .delete:
                guard complete == nil && offset == nil && uploadLength == nil else {
                    throw InvalidRequestError.extraHeaderField
                }
                return (.uploadCancellation, version)
            default:
                throw InvalidRequestError.unknownMethod
            }
        } else {
            if let complete {
                if let offset, offset != 0 {
                    throw InvalidRequestError.invalidPath
                }
                return (
                    .uploadCreation(complete: complete, contentLength: contentLength, uploadLength: uploadLength),
                    version
                )
            } else {
                return nil
            }
        }
    }

    static func stripRequest(_ request: HTTPRequest) -> HTTPRequest {
        var strippedRequest = request
        strippedRequest.headerFields[.uploadComplete] = nil
        strippedRequest.headerFields[.uploadIncomplete] = nil
        strippedRequest.headerFields[.uploadOffset] = nil
        return strippedRequest
    }

    static func processResponse(
        _ response: HTTPResponse,
        offset: Int64,
        resumePath: String,
        forUploadCreation: Bool,
        in context: HTTPResumableUploadContext,
        version: InteropVersion
    ) -> HTTPResponse {
        var finalResponse = response
        finalResponse.headerFields[.uploadDraftInteropVersion] = "\(version.rawValue)"
        if forUploadCreation {
            finalResponse.headerFields[.location] = context.origin + resumePath
        }
        if version >= .v5 {
            finalResponse.headerFields.uploadIncomplete = false
        } else {
            finalResponse.headerFields.uploadComplete = true
        }
        finalResponse.headerFields.uploadOffset = offset
        return finalResponse
    }

    static func processOptionsResponse(_ response: HTTPResponse) -> HTTPResponse {
        var response = response
        if response.status == .notImplemented {
            response = HTTPResponse(status: .ok)
        }
        response.headerFields.uploadLimit = .init(minSize: 0)
        return response
    }
}

extension HTTPField.Name {
    fileprivate static let uploadDraftInteropVersion = Self("Upload-Draft-Interop-Version")!
    fileprivate static let uploadComplete = Self("Upload-Complete")!
    fileprivate static let uploadIncomplete = Self("Upload-Incomplete")!
    fileprivate static let uploadOffset = Self("Upload-Offset")!
    fileprivate static let uploadLength = Self("Upload-Length")!
    fileprivate static let uploadLimit = Self("Upload-Limit")!
}

extension HTTPFields {
    private struct BoolFieldValue: StructuredFieldValue {
        static var structuredFieldType: StructuredFieldValues.StructuredFieldType { .item }
        var item: Bool
    }

    fileprivate var uploadComplete: Bool? {
        get {
            guard let headerValue = self[.uploadComplete] else {
                return nil
            }
            do {
                let value = try StructuredFieldValueDecoder().decode(
                    BoolFieldValue.self,
                    from: Array(headerValue.utf8)
                )
                return value.item
            } catch {
                return nil
            }
        }

        set {
            if let newValue {
                let value = String(
                    decoding: try! StructuredFieldValueEncoder().encode(BoolFieldValue(item: newValue)),
                    as: UTF8.self
                )
                self[.uploadComplete] = value
            } else {
                self[.uploadComplete] = nil
            }
        }
    }

    fileprivate var uploadIncomplete: Bool? {
        get {
            guard let headerValue = self[.uploadIncomplete] else {
                return nil
            }
            do {
                let value = try StructuredFieldValueDecoder().decode(
                    BoolFieldValue.self,
                    from: Array(headerValue.utf8)
                )
                return value.item
            } catch {
                return nil
            }
        }

        set {
            if let newValue {
                let value = String(
                    decoding: try! StructuredFieldValueEncoder().encode(BoolFieldValue(item: newValue)),
                    as: UTF8.self
                )
                self[.uploadIncomplete] = value
            } else {
                self[.uploadIncomplete] = nil
            }
        }
    }

    private struct Int64FieldValue: StructuredFieldValue {
        static var structuredFieldType: StructuredFieldValues.StructuredFieldType { .item }
        var item: Int64
    }

    fileprivate var uploadOffset: Int64? {
        get {
            guard let headerValue = self[.uploadOffset] else {
                return nil
            }
            do {
                let value = try StructuredFieldValueDecoder().decode(
                    Int64FieldValue.self,
                    from: Array(headerValue.utf8)
                )
                return value.item
            } catch {
                return nil
            }
        }

        set {
            if let newValue {
                let value = String(
                    decoding: try! StructuredFieldValueEncoder().encode(Int64FieldValue(item: newValue)),
                    as: UTF8.self
                )
                self[.uploadOffset] = value
            } else {
                self[.uploadOffset] = nil
            }
        }
    }

    fileprivate var uploadLength: Int64? {
        get {
            guard let headerValue = self[.uploadLength] else {
                return nil
            }
            do {
                let value = try StructuredFieldValueDecoder().decode(
                    Int64FieldValue.self,
                    from: Array(headerValue.utf8)
                )
                return value.item
            } catch {
                return nil
            }
        }

        set {
            if let newValue {
                let value = String(
                    decoding: try! StructuredFieldValueEncoder().encode(Int64FieldValue(item: newValue)),
                    as: UTF8.self
                )
                self[.uploadLength] = value
            } else {
                self[.uploadLength] = nil
            }
        }
    }

    fileprivate struct UploadLimitFieldValue: StructuredFieldValue {
        static var structuredFieldType: StructuredFieldValues.StructuredFieldType { .dictionary }
        var maxSize: Int64?
        var minSize: Int64?
        var maxAppendSize: Int64?
        var minAppendSize: Int64?
        var expires: Int64?

        enum CodingKeys: String, CodingKey {
            case maxSize = "max-size"
            case minSize = "min-size"
            case maxAppendSize = "max-append-size"
            case minAppendSize = "min-append-size"
            case expires = "expires"
        }
    }

    fileprivate var uploadLimit: UploadLimitFieldValue? {
        get {
            guard let headerValue = self[.uploadLimit] else {
                return nil
            }
            do {
                let value = try StructuredFieldValueDecoder().decode(
                    UploadLimitFieldValue.self,
                    from: Array(headerValue.utf8)
                )
                return value
            } catch {
                return nil
            }
        }

        set {
            if let newValue {
                let value = String(
                    decoding: try! StructuredFieldValueEncoder().encode(newValue),
                    as: UTF8.self
                )
                self[.uploadLimit] = value
            } else {
                self[.uploadLimit] = nil
            }
        }
    }
}
