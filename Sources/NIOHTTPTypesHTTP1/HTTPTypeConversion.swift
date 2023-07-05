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
import NIOHTTP1

private enum HTTP1TypeConversionError: Error {
    case invalidMethod
    case missingPath
    case invalidStatusCode
}

extension HTTPMethod {
    init(_ newMethod: HTTPRequest.Method) {
        switch newMethod {
        case .get: self = .GET
        case .put: self = .PUT
        case .acl: self = .ACL
        case .head: self = .HEAD
        case .post: self = .POST
        case .copy: self = .COPY
        case .lock: self = .LOCK
        case .move: self = .MOVE
        case .bind: self = .BIND
        case .link: self = .LINK
        case .patch: self = .PATCH
        case .trace: self = .TRACE
        case .mkcol: self = .MKCOL
        case .merge: self = .MERGE
        case .purge: self = .PURGE
        case .notify: self = .NOTIFY
        case .search: self = .SEARCH
        case .unlock: self = .UNLOCK
        case .rebind: self = .REBIND
        case .unbind: self = .UNBIND
        case .report: self = .REPORT
        case .delete: self = .DELETE
        case .unlink: self = .UNLINK
        case .connect: self = .CONNECT
        case .msearch: self = .MSEARCH
        case .options: self = .OPTIONS
        case .propfind: self = .PROPFIND
        case .checkout: self = .CHECKOUT
        case .proppatch: self = .PROPPATCH
        case .subscribe: self = .SUBSCRIBE
        case .mkcalendar: self = .MKCALENDAR
        case .mkactivity: self = .MKACTIVITY
        case .unsubscribe: self = .UNSUBSCRIBE
        case .source: self = .SOURCE
        default: self = .RAW(value: newMethod.rawValue)
        }
    }

    var newMethod: HTTPRequest.Method {
        get throws {
            switch self {
            case .GET: return .get
            case .PUT: return .put
            case .ACL: return .acl
            case .HEAD: return .head
            case .POST: return .post
            case .COPY: return .copy
            case .LOCK: return .lock
            case .MOVE: return .move
            case .BIND: return .bind
            case .LINK: return .link
            case .PATCH: return .patch
            case .TRACE: return .trace
            case .MKCOL: return .mkcol
            case .MERGE: return .merge
            case .PURGE: return .purge
            case .NOTIFY: return .notify
            case .SEARCH: return .search
            case .UNLOCK: return .unlock
            case .REBIND: return .rebind
            case .UNBIND: return .unbind
            case .REPORT: return .report
            case .DELETE: return .delete
            case .UNLINK: return .unlink
            case .CONNECT: return .connect
            case .MSEARCH: return .msearch
            case .OPTIONS: return .options
            case .PROPFIND: return .propfind
            case .CHECKOUT: return .checkout
            case .PROPPATCH: return .proppatch
            case .SUBSCRIBE: return .subscribe
            case .MKCALENDAR: return .mkcalendar
            case .MKACTIVITY: return .mkactivity
            case .UNSUBSCRIBE: return .unsubscribe
            case .SOURCE: return .source
            case .RAW(value: let value):
                guard let method = HTTPRequest.Method(value) else {
                    throw HTTP1TypeConversionError.invalidMethod
                }
                return method
            }
        }
    }
}

extension HTTPHeaders {
    init(_ newFields: HTTPFields) {
        let fields = newFields.map { ($0.name.rawName, $0.value) }
        self.init(fields)
    }

    func newFields(splitCookie: Bool) -> HTTPFields {
        var fields = HTTPFields()
        fields.reserveCapacity(count)
        for (index, field) in enumerated() {
            if index == 0, field.name.lowercased() == "host" {
                continue
            }
            if let name = HTTPField.Name(field.name) {
                if splitCookie, name == .cookie, #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
                    fields.append(contentsOf: field.value.split(separator: "; ", omittingEmptySubsequences: false).map {
                        HTTPField(name: name, value: String($0))
                    })
                } else {
                    fields.append(HTTPField(name: name, value: field.value))
                }
            }
        }
        return fields
    }
}

extension HTTPRequestHead {
    init(_ newRequest: HTTPRequest) throws {
        guard let pathField = newRequest.pseudoHeaderFields.path else {
            throw HTTP1TypeConversionError.missingPath
        }
        var headers = HTTPHeaders()
        headers.reserveCapacity(newRequest.headerFields.count + 1)
        if let authorityField = newRequest.pseudoHeaderFields.authority {
            headers.add(name: "Host", value: authorityField.value)
        }
        var firstCookie = true
        for field in newRequest.headerFields {
            if field.name == .cookie {
                if firstCookie {
                    firstCookie = false
                    headers.add(name: field.name.rawName, value: newRequest.headerFields[.cookie]!)
                }
            } else {
                headers.add(name: field.name.rawName, value: field.value)
            }
        }
        self.init(
            version: .http1_1,
            method: HTTPMethod(newRequest.method),
            uri: pathField.value,
            headers: headers
        )
    }

    func newRequest(secure: Bool, splitCookie: Bool) throws -> HTTPRequest {
        let method = try method.newMethod
        let scheme = secure ? "https" : "http"
        let authority = headers.first.flatMap { $0.name.lowercased() == "host" ? $0.value : nil }
        return HTTPRequest(
            method: method,
            scheme: scheme,
            authority: authority,
            path: uri,
            headerFields: headers.newFields(splitCookie: splitCookie)
        )
    }
}

extension HTTPResponseHead {
    init(_ newResponse: HTTPResponse) {
        self.init(
            version: .http1_1,
            status: HTTPResponseStatus(
                statusCode: newResponse.status.code,
                reasonPhrase: newResponse.status.reasonPhrase
            ),
            headers: HTTPHeaders(newResponse.headerFields)
        )
    }

    var newResponse: HTTPResponse {
        get throws {
            guard status.code <= 999 else {
                throw HTTP1TypeConversionError.invalidStatusCode
            }
            let status = HTTPResponse.Status(code: Int(status.code), reasonPhrase: status.reasonPhrase)
            return HTTPResponse(status: status, headerFields: headers.newFields(splitCookie: false))
        }
    }
}
