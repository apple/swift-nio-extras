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

/// An struct to describe the length of a piece of data in bits
public struct NIOLengthFieldBitLength {
    internal enum Backing {
        case bits8
        case bits16
        case bits24
        case bits32
        case bits64
    }
    internal let bitLength: Backing

    public static let oneByte = NIOLengthFieldBitLength(bitLength: .bits8)
    public static let twoBytes = NIOLengthFieldBitLength(bitLength: .bits16)
    public static let threeBytes = NIOLengthFieldBitLength(bitLength: .bits24)
    public static let fourBytes = NIOLengthFieldBitLength(bitLength: .bits32)
    public static let eightBytes = NIOLengthFieldBitLength(bitLength: .bits64)
    
    public static let eightBits = NIOLengthFieldBitLength(bitLength: .bits8)
    public static let sixteenBits = NIOLengthFieldBitLength(bitLength: .bits16)
    public static let twentyFourBits = NIOLengthFieldBitLength(bitLength: .bits24)
    public static let thirtyTwoBits = NIOLengthFieldBitLength(bitLength: .bits32)
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
