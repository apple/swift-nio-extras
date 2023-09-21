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
        case .head: self = .HEAD
        case .post: self = .POST
        case .put: self = .PUT
        case .delete: self = .DELETE
        case .connect: self = .CONNECT
        case .options: self = .OPTIONS
        case .trace: self = .TRACE
        case .patch: self = .PATCH
        default:
            let rawValue = newMethod.rawValue
            switch rawValue {
            case "ACL": self = .ACL
            case "COPY": self = .COPY
            case "LOCK": self = .LOCK
            case "MOVE": self = .MOVE
            case "BIND": self = .BIND
            case "LINK": self = .LINK
            case "MKCOL": self = .MKCOL
            case "MERGE": self = .MERGE
            case "PURGE": self = .PURGE
            case "NOTIFY": self = .NOTIFY
            case "SEARCH": self = .SEARCH
            case "UNLOCK": self = .UNLOCK
            case "REBIND": self = .REBIND
            case "UNBIND": self = .UNBIND
            case "REPORT": self = .REPORT
            case "UNLINK": self = .UNLINK
            case "MSEARCH": self = .MSEARCH
            case "PROPFIND": self = .PROPFIND
            case "CHECKOUT": self = .CHECKOUT
            case "PROPPATCH": self = .PROPPATCH
            case "SUBSCRIBE": self = .SUBSCRIBE
            case "MKCALENDAR": self = .MKCALENDAR
            case "MKACTIVITY": self = .MKACTIVITY
            case "UNSUBSCRIBE": self = .UNSUBSCRIBE
            case "SOURCE": self = .SOURCE
            default: self = .RAW(value: rawValue)
            }
        }
    }

    var newMethod: HTTPRequest.Method {
        get throws {
            switch self {
            case .GET: return .get
            case .PUT: return .put
            case .ACL: return HTTPRequest.Method("ACL")!
            case .HEAD: return .head
            case .POST: return .post
            case .COPY: return HTTPRequest.Method("COPY")!
            case .LOCK: return HTTPRequest.Method("LOCK")!
            case .MOVE: return HTTPRequest.Method("MOVE")!
            case .BIND: return HTTPRequest.Method("BIND")!
            case .LINK: return HTTPRequest.Method("LINK")!
            case .PATCH: return .patch
            case .TRACE: return .trace
            case .MKCOL: return HTTPRequest.Method("MKCOL")!
            case .MERGE: return HTTPRequest.Method("MERGE")!
            case .PURGE: return HTTPRequest.Method("PURGE")!
            case .NOTIFY: return HTTPRequest.Method("NOTIFY")!
            case .SEARCH: return HTTPRequest.Method("SEARCH")!
            case .UNLOCK: return HTTPRequest.Method("UNLOCK")!
            case .REBIND: return HTTPRequest.Method("REBIND")!
            case .UNBIND: return HTTPRequest.Method("UNBIND")!
            case .REPORT: return HTTPRequest.Method("REPORT")!
            case .DELETE: return .delete
            case .UNLINK: return HTTPRequest.Method("UNLINK")!
            case .CONNECT: return .connect
            case .MSEARCH: return HTTPRequest.Method("MSEARCH")!
            case .OPTIONS: return .options
            case .PROPFIND: return HTTPRequest.Method("PROPFIND")!
            case .CHECKOUT: return HTTPRequest.Method("CHECKOUT")!
            case .PROPPATCH: return HTTPRequest.Method("PROPPATCH")!
            case .SUBSCRIBE: return HTTPRequest.Method("SUBSCRIBE")!
            case .MKCALENDAR: return HTTPRequest.Method("MKCALENDAR")!
            case .MKACTIVITY: return HTTPRequest.Method("MKACTIVITY")!
            case .UNSUBSCRIBE: return HTTPRequest.Method("UNSUBSCRIBE")!
            case .SOURCE: return HTTPRequest.Method("SOURCE")!
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
                if splitCookie && name == .cookie, #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
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
        guard let path = newRequest.method == .connect ? newRequest.authority : newRequest.path else {
            throw HTTP1TypeConversionError.missingPath
        }
        var headers = HTTPHeaders()
        headers.reserveCapacity(newRequest.headerFields.count + 1)
        if let authority = newRequest.authority {
            headers.add(name: "Host", value: authority)
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
            uri: path,
            headers: headers
        )
    }

    func newRequest(secure: Bool, splitCookie: Bool) throws -> HTTPRequest {
        let method = try self.method.newMethod
        let scheme = secure ? "https" : "http"
        let authority = self.headers.first.flatMap { $0.name.lowercased() == "host" ? $0.value : nil }
        return HTTPRequest(
            method: method,
            scheme: scheme,
            authority: authority,
            path: self.uri,
            headerFields: self.headers.newFields(splitCookie: splitCookie)
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
            guard self.status.code <= 999 else {
                throw HTTP1TypeConversionError.invalidStatusCode
            }
            let status = HTTPResponse.Status(code: Int(self.status.code), reasonPhrase: self.status.reasonPhrase)
            return HTTPResponse(status: status, headerFields: self.headers.newFields(splitCookie: false))
        }
    }
}
