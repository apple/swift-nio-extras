//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftNIO project authors
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
    private static let currentInteropVersion = "3"

    static func featureDetectionResponse(resumePath: String, in context: HTTPResumableUploadContext) -> HTTPResponse {
        var response = HTTPResponse(status: .init(code: 104, reasonPhrase: "Upload Resumption Supported"))
        response.headerFields[.uploadDraftInteropVersion] = self.currentInteropVersion
        response.headerFields[.location] = context.origin + resumePath
        return response
    }

    static func offsetRetrievingResponse(offset: Int64, complete: Bool) -> HTTPResponse {
        var response = HTTPResponse(status: .noContent)
        response.headerFields[.uploadDraftInteropVersion] = self.currentInteropVersion
        response.headerFields.uploadIncomplete = !complete
        response.headerFields.uploadOffset = offset
        response.headerFields[.cacheControl] = "no-store"
        return response
    }

    static func incompleteResponse(
        offset: Int64,
        resumePath: String,
        forUploadCreation: Bool,
        in context: HTTPResumableUploadContext
    ) -> HTTPResponse {
        var response = HTTPResponse(status: .created)
        response.headerFields[.uploadDraftInteropVersion] = self.currentInteropVersion
        if forUploadCreation {
            response.headerFields[.location] = context.origin + resumePath
        }
        response.headerFields.uploadIncomplete = true
        response.headerFields.uploadOffset = offset
        return response
    }

    static func cancelledResponse() -> HTTPResponse {
        var response = HTTPResponse(status: .noContent)
        response.headerFields[.uploadDraftInteropVersion] = self.currentInteropVersion
        return response
    }

    static func notFoundResponse() -> HTTPResponse {
        var response = HTTPResponse(status: .notFound)
        response.headerFields[.uploadDraftInteropVersion] = self.currentInteropVersion
        response.headerFields[.contentLength] = "0"
        return response
    }

    static func conflictResponse(offset: Int64, complete: Bool) -> HTTPResponse {
        var response = HTTPResponse(status: .conflict)
        response.headerFields[.uploadDraftInteropVersion] = self.currentInteropVersion
        response.headerFields.uploadIncomplete = !complete
        response.headerFields.uploadOffset = offset
        response.headerFields[.contentLength] = "0"
        return response
    }

    static func badRequestResponse() -> HTTPResponse {
        var response = HTTPResponse(status: .badRequest)
        response.headerFields[.uploadDraftInteropVersion] = self.currentInteropVersion
        response.headerFields[.contentLength] = "0"
        return response
    }

    enum RequestType {
        case notSupported
        case uploadCreation(complete: Bool, contentLength: Int64?)
        case offsetRetrieving
        case uploadAppending(offset: Int64, complete: Bool, contentLength: Int64?)
        case uploadCancellation
        case invalid
    }

    static func identifyRequest(_ request: HTTPRequest, in context: HTTPResumableUploadContext) -> RequestType {
        if request.headerFields[.uploadDraftInteropVersion] != self.currentInteropVersion {
            return .notSupported
        }
        let complete = request.headerFields.uploadIncomplete.map { !$0 }
        let offset = request.headerFields.uploadOffset
        let contentLength = request.headerFields[.contentLength].flatMap(Int64.init)
        if let path = request.path, context.isResumption(path: path) {
            switch request.method {
            case .head:
                guard complete == nil && offset == nil else {
                    return .invalid
                }
                return .offsetRetrieving
            case .patch:
                guard let offset else {
                    return .invalid
                }
                return .uploadAppending(offset: offset, complete: complete ?? true, contentLength: contentLength)
            case .delete:
                guard complete == nil && offset == nil else {
                    return .invalid
                }
                return .uploadCancellation
            default:
                return .invalid
            }
        } else {
            if let complete {
                if let offset, offset != 0 {
                    return .invalid
                }
                return .uploadCreation(complete: complete, contentLength: contentLength)
            } else {
                return .notSupported
            }
        }
    }

    static func stripRequest(_ request: HTTPRequest) -> HTTPRequest {
        var strippedRequest = request
        strippedRequest.headerFields[.uploadIncomplete] = nil
        strippedRequest.headerFields[.uploadOffset] = nil
        return strippedRequest
    }

    static func processResponse(
        _ response: HTTPResponse,
        offset: Int64,
        resumePath: String,
        forUploadCreation: Bool,
        in context: HTTPResumableUploadContext
    ) -> HTTPResponse {
        var finalResponse = response
        finalResponse.headerFields[.uploadDraftInteropVersion] = self.currentInteropVersion
        if forUploadCreation {
            finalResponse.headerFields[.location] = context.origin + resumePath
        }
        finalResponse.headerFields.uploadIncomplete = false
        finalResponse.headerFields.uploadOffset = offset
        return finalResponse
    }
}

private extension HTTPField.Name {
    static let uploadDraftInteropVersion = Self("Upload-Draft-Interop-Version")!
    static let uploadIncomplete = Self("Upload-Incomplete")!
    static let uploadOffset = Self("Upload-Offset")!
}

private extension HTTPFields {
    private struct UploadIncompleteFieldValue: StructuredFieldValue {
        static var structuredFieldType: StructuredFieldValues.StructuredFieldType { .item }
        var item: Bool
    }

    var uploadIncomplete: Bool? {
        get {
            guard let headerValue = self[.uploadIncomplete] else {
                return nil
            }
            do {
                let value = try StructuredFieldValueDecoder().decode(UploadIncompleteFieldValue.self, from: Array(headerValue.utf8))
                return value.item
            } catch {
                return nil
            }
        }

        set {
            if let newValue {
                let value = String(decoding: try! StructuredFieldValueEncoder().encode(UploadIncompleteFieldValue(item: newValue)), as: UTF8.self)
                self[.uploadIncomplete] = value
            } else {
                self[.uploadIncomplete] = nil
            }
        }
    }

    private struct UploadOffsetFieldValue: StructuredFieldValue {
        static var structuredFieldType: StructuredFieldValues.StructuredFieldType { .item }
        var item: Int64
    }

    var uploadOffset: Int64? {
        get {
            guard let headerValue = self[.uploadOffset] else {
                return nil
            }
            do {
                let value = try StructuredFieldValueDecoder().decode(UploadOffsetFieldValue.self, from: Array(headerValue.utf8))
                return value.item
            } catch {
                return nil
            }
        }

        set {
            if let newValue {
                let value = String(decoding: try! StructuredFieldValueEncoder().encode(UploadOffsetFieldValue(item: newValue)), as: UTF8.self)
                self[.uploadOffset] = value
            } else {
                self[.uploadOffset] = nil
            }
        }
    }
}
