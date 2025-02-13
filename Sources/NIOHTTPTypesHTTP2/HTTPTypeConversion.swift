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
import NIOHPACK

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
    fileprivate init(_ newIndexingStrategy: HTTPField.DynamicTableIndexingStrategy) {
        switch newIndexingStrategy {
        case .avoid: self = .nonIndexable
        case .disallow: self = .neverIndexed
        default: self = .indexable
        }
    }
}

extension HTTPField.DynamicTableIndexingStrategy {
    fileprivate init(_ oldIndexing: HPACKIndexing) {
        switch oldIndexing {
        case .indexable: self = .automatic
        case .nonIndexable: self = .avoid
        case .neverIndexed: self = .disallow
        }
    }
}

extension HPACKHeaders {
    private mutating func add(newField field: HTTPField) {
        self.add(name: field.name.canonicalName, value: field.value, indexing: HPACKIndexing(field.indexingStrategy))
    }

    init(_ newRequest: HTTPRequest) {
        self.init()
        self.reserveCapacity(newRequest.headerFields.count + 5)

        self.add(newField: newRequest.pseudoHeaderFields.method)
        if let field = newRequest.pseudoHeaderFields.scheme {
            self.add(newField: field)
        }
        if let field = newRequest.pseudoHeaderFields.authority {
            self.add(newField: field)
        }
        if let field = newRequest.pseudoHeaderFields.path {
            self.add(newField: field)
        }
        if let field = newRequest.pseudoHeaderFields.extendedConnectProtocol {
            self.add(newField: field)
        }
        for field in newRequest.headerFields {
            self.add(newField: field)
        }
    }

    init(_ newResponse: HTTPResponse) {
        self.init()
        self.reserveCapacity(newResponse.headerFields.count + 1)

        self.add(newField: newResponse.pseudoHeaderFields.status)
        for field in newResponse.headerFields {
            self.add(newField: field)
        }
    }

    init(_ newTrailers: HTTPFields) {
        self.init()
        self.reserveCapacity(newTrailers.count)

        for field in newTrailers {
            self.add(newField: field)
        }
    }
}

extension HTTPRequest {
    init(_ hpack: HPACKHeaders) throws {
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

        var i = hpack.startIndex
        while i != hpack.endIndex {
            let (name, value, indexable) = hpack[i]
            if name.utf8.first != UInt8(ascii: ":") {
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
            i = hpack.index(after: i)
        }

        guard let methodString else {
            throw HTTP2TypeConversionError.missingMethod
        }
        guard let method = HTTPRequest.Method(methodString) else {
            throw HTTP2TypeConversionError.invalidMethod
        }

        self.init(
            method: method,
            scheme: schemeString,
            authority: authorityString,
            path: pathString
        )
        self.pseudoHeaderFields.method.indexingStrategy = .init(methodIndexable)
        self.pseudoHeaderFields.scheme?.indexingStrategy = .init(schemeIndexable)
        self.pseudoHeaderFields.authority?.indexingStrategy = .init(authorityIndexable)
        self.pseudoHeaderFields.path?.indexingStrategy = .init(pathIndexable)
        if let protocolString {
            self.extendedConnectProtocol = protocolString
            self.pseudoHeaderFields.extendedConnectProtocol?.indexingStrategy = .init(protocolIndexable)
        }

        self.headerFields.reserveCapacity(hpack.count)
        while i != hpack.endIndex {
            let (name, value, indexable) = hpack[i]
            if name.utf8.first == UInt8(ascii: ":") {
                throw HTTP2TypeConversionError.pseudoFieldNotFirst
            }
            if let fieldName = HTTPField.Name(name) {
                var field = HTTPField(name: fieldName, value: value)
                field.indexingStrategy = .init(indexable)
                self.headerFields.append(field)
            }
            i = hpack.index(after: i)
        }
    }
}

extension HTTPResponse {
    init(_ hpack: HPACKHeaders) throws {
        var statusString: String? = nil
        var statusIndexable: HPACKIndexing = .indexable

        var i = hpack.startIndex
        while i != hpack.endIndex {
            let (name, value, indexable) = hpack[i]
            if name.utf8.first != UInt8(ascii: ":") {
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
            i = hpack.index(after: i)
        }

        guard let statusString else {
            throw HTTP2TypeConversionError.missingStatus
        }
        guard let status = Int(statusString),
            (0...999).contains(status)
        else {
            throw HTTP2TypeConversionError.invalidStatus
        }

        self.init(status: HTTPResponse.Status(code: status))
        self.pseudoHeaderFields.status.indexingStrategy = .init(statusIndexable)

        self.headerFields.reserveCapacity(hpack.count)
        while i != hpack.endIndex {
            let (name, value, indexable) = hpack[i]
            if name.utf8.first == UInt8(ascii: ":") {
                throw HTTP2TypeConversionError.pseudoFieldNotFirst
            }
            if let fieldName = HTTPField.Name(name) {
                var field = HTTPField(name: fieldName, value: value)
                field.indexingStrategy = .init(indexable)
                self.headerFields.append(field)
            }
            i = hpack.index(after: i)
        }
    }
}

extension HTTPFields {
    init(trailers: HPACKHeaders) throws {
        self.init()
        self.reserveCapacity(trailers.count)

        for (name, value, indexable) in trailers {
            if name.utf8.first == UInt8(ascii: ":") {
                throw HTTP2TypeConversionError.pseudoFieldInTrailers
            }
            if let fieldName = HTTPField.Name(name) {
                var field = HTTPField(name: fieldName, value: value)
                field.indexingStrategy = .init(indexable)
                self.append(field)
            }
        }
    }
}
