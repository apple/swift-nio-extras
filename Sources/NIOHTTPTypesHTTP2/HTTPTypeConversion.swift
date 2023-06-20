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

import NIOHPACK
import HTTPTypes

private enum HTTP2TypeConversionError: Error {
    case multipleMethod
    case multipleScheme
    case multipleAuthority
    case multiplePath
    case multipleProtocol
    case missingMethod
    case invalidMethod

    case multipleStatus
    case missingStatus
    case invalidStatus

    case pseudoFieldNotFirst
    case pseudoFieldInTrailers
}

extension HPACKIndexing {
    init(_ newIndexingStrategy: HTTPField.DynamicTableIndexingStrategy) {
        switch newIndexingStrategy {
        case .avoid: self = .nonIndexable
        case .disallow: self = .neverIndexed
        default: self = .indexable
        }
    }

    var newIndexingStrategy: HTTPField.DynamicTableIndexingStrategy {
        switch self {
        case .indexable: return .automatic
        case .nonIndexable: return .avoid
        case .neverIndexed: return .disallow
        }
    }
}

extension HPACKHeaders {
    mutating func add(newField field: HTTPField) {
        add(name: field.name.canonicalName, value: field.value, indexing: HPACKIndexing(field.indexingStrategy))
    }

    init(_ newRequest: HTTPRequest) {
        var headers = HPACKHeaders()
        headers.reserveCapacity(newRequest.headerFields.count + 5)

        headers.add(newField: newRequest.pseudoHeaderFields.method)
        if let field = newRequest.pseudoHeaderFields.scheme {
            headers.add(newField: field)
        }
        if let field = newRequest.pseudoHeaderFields.authority {
            headers.add(newField: field)
        }
        if let field = newRequest.pseudoHeaderFields.path {
            headers.add(newField: field)
        }
        if let field = newRequest.pseudoHeaderFields.extendedConnectProtocol {
            headers.add(newField: field)
        }
        for field in newRequest.headerFields {
            headers.add(newField: field)
        }
        self = headers
    }

    init(_ newResponse: HTTPResponse) {
        var headers = HPACKHeaders()
        headers.reserveCapacity(newResponse.headerFields.count + 1)

        headers.add(newField: newResponse.pseudoHeaderFields.status)
        for field in newResponse.headerFields {
            headers.add(newField: field)
        }
        self = headers
    }

    init(_ newTrailers: HTTPFields) {
        var headers = HPACKHeaders()
        headers.reserveCapacity(newTrailers.count)
        for field in newTrailers {
            headers.add(newField: field)
        }
        self = headers
    }

    var newRequest: HTTPRequest {
        get throws {
            var methodString: String? = nil
            var methodIndexable: HPACKIndexing = .indexable
            var schemeString: String? = nil
            var schemeIndexable: HPACKIndexing = .indexable
            var authorityString: String? = nil
            var authorityIndexable: HPACKIndexing = .indexable
            var pathString: String? = nil
            var pathIndexable: HPACKIndexing = .indexable
            var protocolString: String? = nil
            var protocolIndexable: HPACKIndexing = .indexable

            var i = startIndex
            while i != endIndex {
                let (name, value, indexable) = self[i]
                if !name.hasPrefix(":") {
                    break
                }
                switch name {
                case ":method":
                    if methodString != nil {
                        throw HTTP2TypeConversionError.multipleMethod
                    }
                    methodString = value
                    methodIndexable = indexable
                case ":scheme":
                    if schemeString != nil {
                        throw HTTP2TypeConversionError.multipleScheme
                    }
                    schemeString = value
                    schemeIndexable = indexable
                case ":authority":
                    if authorityString != nil {
                        throw HTTP2TypeConversionError.multipleAuthority
                    }
                    authorityString = value
                    authorityIndexable = indexable
                case ":path":
                    if pathString != nil {
                        throw HTTP2TypeConversionError.multiplePath
                    }
                    pathString = value
                    pathIndexable = indexable
                case ":protocol":
                    if protocolString != nil {
                        throw HTTP2TypeConversionError.multipleProtocol
                    }
                    protocolString = value
                    protocolIndexable = indexable
                default:
                    continue
                }
                i = index(after: i)
            }

            guard let methodString else {
                throw HTTP2TypeConversionError.missingMethod
            }
            guard let method = HTTPRequest.Method(methodString) else {
                throw HTTP2TypeConversionError.invalidMethod
            }

            var request = HTTPRequest(method: method,
                                      scheme: schemeString,
                                      authority: authorityString,
                                      path: pathString)
            request.pseudoHeaderFields.method.indexingStrategy = methodIndexable.newIndexingStrategy
            request.pseudoHeaderFields.scheme?.indexingStrategy = schemeIndexable.newIndexingStrategy
            request.pseudoHeaderFields.authority?.indexingStrategy = authorityIndexable.newIndexingStrategy
            request.pseudoHeaderFields.path?.indexingStrategy = pathIndexable.newIndexingStrategy
            if let protocolString {
                request.extendedConnectProtocol = protocolString
                request.pseudoHeaderFields.extendedConnectProtocol?.indexingStrategy = protocolIndexable.newIndexingStrategy
            }

            request.headerFields.reserveCapacity(count)
            while i != endIndex {
                let (name, value, indexable) = self[i]
                if name.hasPrefix(":") {
                    throw HTTP2TypeConversionError.pseudoFieldNotFirst
                }
                if let fieldName = HTTPField.Name(name) {
                    var field = HTTPField(name: fieldName, value: value)
                    field.indexingStrategy = indexable.newIndexingStrategy
                    request.headerFields.append(field)
                }
                i = index(after: i)
            }
            return request
        }
    }

    var newResponse: HTTPResponse {
        get throws {
            var statusString: String? = nil
            var statusIndexable: HPACKIndexing = .indexable

            var i = startIndex
            while i != endIndex {
                let (name, value, indexable) = self[i]
                if !name.hasPrefix(":") {
                    break
                }
                switch name {
                case ":status":
                    if statusString != nil {
                        throw HTTP2TypeConversionError.multipleStatus
                    }
                    statusString = value
                    statusIndexable = indexable
                default:
                    continue
                }
                i = index(after: i)
            }

            guard let statusString else {
                throw HTTP2TypeConversionError.missingStatus
            }
            guard let status = Int(statusString),
                  (0...999).contains(status) else {
                throw HTTP2TypeConversionError.invalidStatus
            }

            var response = HTTPResponse(status: HTTPResponse.Status(code: status))
            response.pseudoHeaderFields.status.indexingStrategy = statusIndexable.newIndexingStrategy

            response.headerFields.reserveCapacity(count)
            while i != endIndex {
                let (name, value, indexable) = self[i]
                if name.hasPrefix(":") {
                    throw HTTP2TypeConversionError.pseudoFieldNotFirst
                }
                if let fieldName = HTTPField.Name(name) {
                    var field = HTTPField(name: fieldName, value: value)
                    field.indexingStrategy = indexable.newIndexingStrategy
                    response.headerFields.append(field)
                }
                i = index(after: i)
            }
            return response
        }
    }

    var newTrailers: HTTPFields {
        get throws {
            var fields = HTTPFields()
            fields.reserveCapacity(count)
            for (name, value, indexable) in self {
                if name.hasPrefix(":") {
                    throw HTTP2TypeConversionError.pseudoFieldInTrailers
                }
                if let fieldName = HTTPField.Name(name) {
                    var field = HTTPField(name: fieldName, value: value)
                    field.indexingStrategy = indexable.newIndexingStrategy
                    fields.append(field)
                }
            }
            return fields
        }
    }
}
