//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

/// A struct to describe the length of a piece of data in bits
public struct NIOLengthFieldBitLength: Sendable {
    internal enum Backing {
        case bits8
        case bits16
        case bits24
        case bits32
        case bits64
    }
    internal let bitLength: Backing

    /// One byte - the same as ``eightBits``
    public static let oneByte = NIOLengthFieldBitLength(bitLength: .bits8)
    /// Two bytes - the same as ``sixteenBits``
    public static let twoBytes = NIOLengthFieldBitLength(bitLength: .bits16)
    /// Three bytes - the same as ``twentyFourBits``
    public static let threeBytes = NIOLengthFieldBitLength(bitLength: .bits24)
    /// Four bytes - the same as ``thirtyTwoBits``
    public static let fourBytes = NIOLengthFieldBitLength(bitLength: .bits32)
    /// Eight bytes - the same as ``sixtyFourBits``
    public static let eightBytes = NIOLengthFieldBitLength(bitLength: .bits64)

    /// Eight bits - the same as ``oneByte``
    public static let eightBits = NIOLengthFieldBitLength(bitLength: .bits8)
    /// Sixteen bits - the same as ``twoBytes``
    public static let sixteenBits = NIOLengthFieldBitLength(bitLength: .bits16)
    /// Twenty-four bits - the same as ``threeBytes``
    public static let twentyFourBits = NIOLengthFieldBitLength(bitLength: .bits24)
    /// Thirty-two bits - the same as ``fourBytes``
    public static let thirtyTwoBits = NIOLengthFieldBitLength(bitLength: .bits32)
    /// Sixty-four bits - the same as ``eightBytes``
    public static let sixtyFourBits = NIOLengthFieldBitLength(bitLength: .bits64)

    internal var length: Int {
        switch bitLength {
        case .bits8:
            return 1
        case .bits16:
            return 2
        case .bits24:
            return 3
        case .bits32:
            return 4
        case .bits64:
            return 8
        }
    }

    internal var max: UInt {
        switch bitLength {
        case .bits8:
            return UInt(UInt8.max)
        case .bits16:
            return UInt(UInt16.max)
        case .bits24:
            return (UInt(UInt16.max) << 8) &+ UInt(UInt8.max)
        case .bits32:
            return UInt(UInt32.max)
        case .bits64:
            return UInt(UInt64.max)
        }
    }
}
