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
}

extension HTTPRequest.Method {
    init(_ oldMethod: HTTPMethod) throws {
        switch oldMethod {
        case .GET: self = .get
        case .PUT: self = .put
        case .ACL: self = .init("ACL")!
        case .HEAD: self = .head
        case .POST: self = .post
        case .COPY: self = .init("COPY")!
        case .LOCK: self = .init("LOCK")!
        case .MOVE: self = .init("MOVE")!
        case .BIND: self = .init("BIND")!
        case .LINK: self = .init("LINK")!
        case .PATCH: self = .patch
        case .TRACE: self = .trace
        case .MKCOL: self = .init("MKCOL")!
        case .MERGE: self = .init("MERGE")!
        case .PURGE: self = .init("PURGE")!
        case .NOTIFY: self = .init("NOTIFY")!
        case .SEARCH: self = .init("SEARCH")!
        case .UNLOCK: self = .init("UNLOCK")!
        case .REBIND: self = .init("REBIND")!
        case .UNBIND: self = .init("UNBIND")!
        case .REPORT: self = .init("REPORT")!
        case .DELETE: self = .delete
        case .UNLINK: self = .init("UNLINK")!
        case .CONNECT: self = .connect
        case .MSEARCH: self = .init("MSEARCH")!
        case .OPTIONS: self = .options
        case .PROPFIND: self = .init("PROPFIND")!
        case .CHECKOUT: self = .init("CHECKOUT")!
        case .PROPPATCH: self = .init("PROPPATCH")!
        case .SUBSCRIBE: self = .init("SUBSCRIBE")!
        case .MKCALENDAR: self = .init("MKCALENDAR")!
        case .MKACTIVITY: self = .init("MKACTIVITY")!
        case .UNSUBSCRIBE: self = .init("UNSUBSCRIBE")!
        case .SOURCE: self = .init("SOURCE")!
        case .RAW(value: let value):
            guard let method = HTTPRequest.Method(value) else {
                throw HTTP1TypeConversionError.invalidMethod
            }
            self = method
        }
    }
}

extension HTTPHeaders {
    init(_ newFields: HTTPFields) {
        let fields = newFields.map { ($0.name.rawName, $0.value) }
        self.init(fields)
    }
}

extension HTTPFields {
    init(_ oldHeaders: HTTPHeaders, splitCookie: Bool) {
        self.init()
        self.reserveCapacity(count)
        for (index, field) in oldHeaders.enumerated() {
            if index == 0, field.name.lowercased() == "host" {
                continue
            }
            if let name = HTTPField.Name(field.name) {
                if splitCookie && name == .cookie, #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
                    self.append(contentsOf: field.value.split(separator: "; ", omittingEmptySubsequences: false).map {
                        HTTPField(name: name, value: String($0))
                    })
                } else {
                    self.append(HTTPField(name: name, value: field.value))
                }
            }
        }
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
}

extension HTTPRequest {
    init(_ oldRequest: HTTPRequestHead, secure: Bool, splitCookie: Bool) throws {
        let method = try Method(oldRequest.method)
        let scheme = secure ? "https" : "http"
        let authority = oldRequest.headers.first.flatMap { $0.name.lowercased() == "host" ? $0.value : nil }
        self.init(
            method: method,
            scheme: scheme,
            authority: authority,
            path: oldRequest.uri,
            headerFields: HTTPFields(oldRequest.headers, splitCookie: splitCookie)
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
}

extension HTTPResponse {
    init(_ oldResponse: HTTPResponseHead) throws {
        guard oldResponse.status.code <= 999 else {
            throw HTTP1TypeConversionError.invalidStatusCode
        }
        let status = HTTPResponse.Status(code: Int(oldResponse.status.code), reasonPhrase: oldResponse.status.reasonPhrase)
        self.init(status: status, headerFields: HTTPFields(oldResponse.headers, splitCookie: false))
    }
}
