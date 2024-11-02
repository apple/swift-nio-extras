//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

public struct RPCFragmentHeader: Hashable & Sendable {
    public var length: UInt32
    public var last: Bool

    public init(length: UInt32, last: Bool) {
        self.length = length
        self.last = last
    }

    public init(rawValue: UInt32) {
        let last = rawValue & (1 << 31) == 0 ? false : true
        let length = rawValue & (UInt32.max ^ (1 << 31))

        self = .init(length: length, last: last)
    }

    public var rawValue: UInt32 {
        var rawValue = self.length
        rawValue |= ((self.last ? 1 : 0) << 31)
        return rawValue
    }
}

public enum RPCMessageType: UInt32, Hashable & Sendable {
    case call = 0
    case reply = 1
}

/// RFC 5531: struct rpc_msg
public enum RPCMessage: Hashable & Sendable {
    case call(RPCCall)
    case reply(RPCReply)

    var xid: UInt32 {
        get {
            switch self {
            case .call(let call):
                return call.xid
            case .reply(let reply):
                return reply.xid
            }
        }
        set {
            switch self {
            case .call(var call):
                call.xid = newValue
                self = .call(call)
            case .reply(var reply):
                reply.xid = newValue
                self = .reply(reply)
            }
        }
    }
}

/// RFC 5531: struct call_body
public struct RPCCall: Hashable & Sendable {
    public init(
        xid: UInt32,
        rpcVersion: UInt32,
        program: UInt32,
        programVersion: UInt32,
        procedure: UInt32,
        credentials: RPCCredentials,
        verifier: RPCOpaqueAuth
    ) {
        self.xid = xid
        self.rpcVersion = rpcVersion
        self.program = program
        self.programVersion = programVersion
        self.procedure = procedure
        self.credentials = credentials
        self.verifier = verifier
    }

    public var xid: UInt32
    public var rpcVersion: UInt32  // must be 2
    public var program: UInt32
    public var programVersion: UInt32
    public var procedure: UInt32
    public var credentials: RPCCredentials
    public var verifier: RPCOpaqueAuth
}

extension RPCCall {
    public var programAndProcedure: RPCNFS3ProcedureID {
        get {
            RPCNFS3ProcedureID(program: self.program, procedure: self.procedure)
        }
        set {
            self.program = newValue.program
            self.procedure = newValue.procedure
        }
    }
}

public enum RPCReplyStatus: Hashable & Sendable {
    case messageAccepted(RPCAcceptedReply)
    case messageDenied(RPCRejectedReply)
}

public struct RPCReply: Hashable & Sendable {
    public var xid: UInt32
    public var status: RPCReplyStatus

    public init(xid: UInt32, status: RPCReplyStatus) {
        self.xid = xid
        self.status = status
    }
}

public enum RPCAcceptedReplyStatus: Hashable & Sendable {
    case success
    case programUnavailable
    case programMismatch(low: UInt32, high: UInt32)
    case procedureUnavailable
    case garbageArguments
    case systemError
}

public struct RPCOpaqueAuth: Hashable & Sendable {
    public var flavor: RPCAuthFlavor
    public var opaque: ByteBuffer? = nil

    public init(flavor: RPCAuthFlavor, opaque: ByteBuffer? = nil) {
        self.flavor = flavor
        self.opaque = opaque
    }
}

public struct RPCAcceptedReply: Hashable & Sendable {
    public var verifier: RPCOpaqueAuth
    public var status: RPCAcceptedReplyStatus

    public init(verifier: RPCOpaqueAuth, status: RPCAcceptedReplyStatus) {
        self.verifier = verifier
        self.status = status
    }
}

public enum RPCAuthStatus: UInt32, Hashable & Sendable {
    case ok = 0  // success
    case badCredentials = 1  // bad credential (seal broken)
    case rejectedCredentials = 2  // client must begin new session
    case badVerifier = 3  // bad verifier (seal broken)
    case rejectedVerifier = 4  // verifier expired or replayed
    case rejectedForSecurityReasons = 5  // rejected for security reasons
    case invalidResponseVerifier = 6  // bogus response verifier
    case failedForUnknownReason = 7  // reason unknown
    case kerberosError = 8  // kerberos generic error
    case credentialExpired = 9  // time of credential expired
    case ticketFileProblem = 10  // problem with ticket file
    case cannotDecodeAuthenticator = 11  // can't decode authenticator
    case illegalNetworkAddressInTicket = 12  // wrong net address in ticket
    case noCredentialsForUser = 13  // no credentials for user
    case problemWithGSSContext = 14  // problem with context
}

public enum RPCRejectedReply: Hashable & Sendable {
    case rpcMismatch(low: UInt32, high: UInt32)
    case authError(RPCAuthStatus)
}

public enum RPCErrors: Error {
    case unknownType(UInt32)
    case tooLong(RPCFragmentHeader, xid: UInt32, messageType: UInt32)
    case fragementHeaderLengthTooShort(UInt32)
    case unknownVerifier(UInt32)
    case unknownVersion(UInt32)
    case invalidAuthFlavor(UInt32)
    case illegalReplyStatus(UInt32)
    case illegalReplyAcceptanceStatus(UInt32)
    case illegalReplyRejectionStatus(UInt32)
    case illegalAuthStatus(UInt32)
}

public struct RPCCredentials: Hashable & Sendable {
    internal var flavor: UInt32
    internal var length: UInt32
    internal var otherBytes: ByteBuffer

    public init(flavor: UInt32, length: UInt32, otherBytes: ByteBuffer) {
        self.flavor = flavor
        self.length = length
        self.otherBytes = otherBytes
    }
}

public enum RPCAuthFlavor: UInt32, Hashable & Sendable {
    case noAuth = 0
    case system = 1
    case short = 2
    case dh = 3
    case rpcSecGSS = 6

    public static let unix: Self = .system
}
