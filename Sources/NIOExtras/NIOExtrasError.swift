//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2025 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import NIOCore

/// Base type for errors from NIOExtras
public protocol NIOExtrasError: Equatable, Error {}

/// Errors that are raised in NIOExtras.
public enum NIOExtrasErrors: Sendable {

    /// Error indicating that after an operation some unused bytes are left.
    public struct LeftOverBytesError: NIOExtrasError {
        public let leftOverBytes: ByteBuffer
    }

    /// The channel was closed before receiving a response to a request.
    public struct ClosedBeforeReceivingResponse: NIOExtrasError {}

    /// Error indicating the response promise buffer is empty.
    public struct ResponsePromiseBufferEmpty: NIOExtrasError {}
}
