//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import XCTest
import NIONFS3
import NIOCore

final class NFS3ReplyEncoderTest: XCTestCase {
    func testPartialReadEncoding() {
        for payloadLength in 0..<100 {
            let expectedPayload = ByteBuffer(repeating: UInt8(ascii: "j"), count: payloadLength)
            let expectedFillBytes = (4 - (payloadLength % 4)) % 4

            let reply = RPCNFS3Reply(rpcReply: RPCReply(xid: 12345,
                                                       status: .messageAccepted(.init(verifier: .init(flavor: .noAuth,
                                                                                                      opaque: nil),
                                                                                      status: .success))),
                                    nfsReply: .read(.init(result: .okay(.init(attributes: nil,
                                                                              count: 7,
                                                                              eof: false,
                                                                              data: expectedPayload)))))

            var partialSerialisation = ByteBuffer()
            let (bytesWritten, nextStep) = partialSerialisation.writeRPCNFSReplyPartially(reply)
            XCTAssertEqual(partialSerialisation.readableBytes, bytesWritten)
            switch nextStep {
            case .doNothing:
                XCTFail("we need to write more bytes here")
            case .writeBlob(let actualPayload, numberOfFillBytes: let fillBytes):
                XCTAssertEqual(expectedPayload, actualPayload)
                XCTAssertEqual(expectedFillBytes, fillBytes)
            }

            var fullSerialisation = ByteBuffer()
            let bytesWruttenFull = fullSerialisation.writeRPCNFSReply(reply)
            XCTAssertEqual(bytesWruttenFull, fullSerialisation.readableBytes)

            XCTAssert(fullSerialisation.readableBytesView.starts(with: partialSerialisation.readableBytesView))
            XCTAssert(fullSerialisation.readableBytesView
                        .dropFirst(partialSerialisation.readableBytes)
                        .prefix(expectedPayload.readableBytes)
                        .elementsEqual(expectedPayload.readableBytesView))

            XCTAssertEqual(partialSerialisation.readableBytes + payloadLength + expectedFillBytes,
                           fullSerialisation.readableBytes)
            XCTAssertEqual(UInt32(payloadLength),
                           partialSerialisation.getInteger(at: partialSerialisation.writerIndex - 4,
                                                           endianness: .big,
                                                           as: UInt32.self))
        }
    }

    func testFullReadEncodingParses() {
        for payloadLength in 0..<1 {
            let expectedPayload = ByteBuffer(repeating: UInt8(ascii: "j"), count: payloadLength)

            let expectedReply = RPCNFS3Reply(rpcReply: RPCReply(xid: 12345,
                                                               status: .messageAccepted(.init(verifier: .init(flavor: .noAuth,
                                                                                                              opaque: nil),
                                                                                              status: .success))),
                                            nfsReply: .read(.init(result: .okay(.init(attributes: nil,
                                                                                      count: 7,
                                                                                      eof: false,
                                                                                      data: expectedPayload)))))

            var fullSerialisation = ByteBuffer()
            let bytesWrittenFull = fullSerialisation.writeRPCNFSReply(expectedReply)
            XCTAssertEqual(bytesWrittenFull, fullSerialisation.readableBytes)
            guard var actualReply = try? fullSerialisation.readRPCMessage() else {
                XCTFail("could not read RPC message")
                return
            }
            XCTAssertEqual(0, fullSerialisation.readableBytes)
            var actualNFSReply: NFS3ReplyRead? = nil
            XCTAssertNoThrow(actualNFSReply = try actualReply.1.readNFSReplyRead())
            XCTAssertEqual(0, actualReply.1.readableBytes)
            XCTAssertEqual(expectedReply.nfsReply,
                           actualNFSReply.map { .read($0) },
                           "parsing failed for payload length \(payloadLength)")
        }
    }
}
