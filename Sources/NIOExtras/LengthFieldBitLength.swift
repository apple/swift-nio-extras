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

import Foundation

/// An struct to describe the length of a piece of data in bits
public struct LengthFieldBitLength {
    internal enum Backing {
        case bits8
        case bits16
        case bits24
        case bits32
        case bits64
    }
    internal let bitLength: Backing

    public static let oneByte = LengthFieldBitLength(bitLength: .bits8)
    public static let twoBytes = LengthFieldBitLength(bitLength: .bits16)
    public static let threeBytes = LengthFieldBitLength(bitLength: .bits24)
    public static let fourBytes = LengthFieldBitLength(bitLength: .bits32)
    public static let eightBytes = LengthFieldBitLength(bitLength: .bits64)
    
    public static let eightBits = LengthFieldBitLength(bitLength: .bits8)
    public static let sixteenBits = LengthFieldBitLength(bitLength: .bits16)
    public static let twentyFourBits = LengthFieldBitLength(bitLength: .bits24)
    public static let thirtyTwoBits = LengthFieldBitLength(bitLength: .bits32)
    public static let sixtyFourBits = LengthFieldBitLength(bitLength: .bits64)
    
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
