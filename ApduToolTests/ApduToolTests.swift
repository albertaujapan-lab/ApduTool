//
//  ApduToolTests.swift
//  ApduToolTests
//
//  Created by Ken Cheung on 1/26/23.
//

import XCTest
@testable import ApduTool

final class ApduToolTests: XCTestCase {

    var pcsc: Pcsc!

    override func setUpWithError() throws {
        try super.setUpWithError()
        pcsc = Pcsc()
    }

    override func tearDownWithError() throws {
        pcsc = nil
        try super.tearDownWithError()
    }

    // MARK: - Short APDU Parsing Tests (ISO 7816-4)

    func testCase1ShortApdu() throws {
        let bytes: [UInt8] = [0x00, 0xA4, 0x00, 0x00]
        let cmd = pcsc.parseAPDU(bytes)
        XCTAssertEqual(cmd.cla, 0x00)
        XCTAssertEqual(cmd.ins, 0xA4)
        XCTAssertEqual(cmd.p1, 0x00)
        XCTAssertEqual(cmd.p2, 0x00)
        XCTAssertNil(cmd.data)
        XCTAssertNil(cmd.le)
        XCTAssertFalse(cmd.isExtended)
    }

    func testCase2SShortApdu() throws {
        // Le = 0x10 (16 bytes)
        let bytes: [UInt8] = [0x00, 0xB0, 0x00, 0x00, 0x10]
        let cmd = pcsc.parseAPDU(bytes)
        XCTAssertEqual(cmd.cla, 0x00)
        XCTAssertEqual(cmd.ins, 0xB0)
        XCTAssertEqual(cmd.p1, 0x00)
        XCTAssertEqual(cmd.p2, 0x00)
        XCTAssertNil(cmd.data)
        XCTAssertEqual(cmd.le, 16)
        XCTAssertFalse(cmd.isExtended)

        // Le = 0x00 -> 256 bytes in ISO 7816-4
        let bytes256: [UInt8] = [0x00, 0xB0, 0x01, 0x00, 0x00]
        let cmd256 = pcsc.parseAPDU(bytes256)
        XCTAssertEqual(cmd256.le, 256)
    }

    func testCase3SShortApdu() throws {
        // Lc = 0x02, Data = [0x3F, 0x00]
        let bytes: [UInt8] = [0x00, 0xA4, 0x04, 0x00, 0x02, 0x3F, 0x00]
        let cmd = pcsc.parseAPDU(bytes)
        XCTAssertEqual(cmd.cla, 0x00)
        XCTAssertEqual(cmd.ins, 0xA4)
        XCTAssertEqual(cmd.p1, 0x04)
        XCTAssertEqual(cmd.p2, 0x00)
        XCTAssertEqual(cmd.data?.bytes, [0x3F, 0x00])
        XCTAssertNil(cmd.le)
        XCTAssertFalse(cmd.isExtended)
    }

    func testCase4SShortApdu() throws {
        // Lc = 0x02, Data = [0x3F, 0x00], Le = 0x20 (32 bytes)
        let bytes: [UInt8] = [0x00, 0xA4, 0x04, 0x00, 0x02, 0x3F, 0x00, 0x20]
        let cmd = pcsc.parseAPDU(bytes)
        XCTAssertEqual(cmd.cla, 0x00)
        XCTAssertEqual(cmd.ins, 0xA4)
        XCTAssertEqual(cmd.p1, 0x04)
        XCTAssertEqual(cmd.p2, 0x00)
        XCTAssertEqual(cmd.data?.bytes, [0x3F, 0x00])
        XCTAssertEqual(cmd.le, 32)
        XCTAssertFalse(cmd.isExtended)
    }

    // MARK: - Extended APDU Parsing Tests (ISO 7816-4)

    func testCase2EExtendedApdu() throws {
        // 7 bytes: CLA INS P1 P2 00 Le1 Le2 -> Le = 0x0200 = 512 bytes
        let bytes: [UInt8] = [0x00, 0xB0, 0x00, 0x00, 0x00, 0x02, 0x00]
        let cmd = pcsc.parseAPDU(bytes)
        XCTAssertEqual(cmd.cla, 0x00)
        XCTAssertEqual(cmd.ins, 0xB0)
        XCTAssertNil(cmd.data)
        XCTAssertEqual(cmd.le, 512)
        XCTAssertTrue(cmd.isExtended)

        // Le1 Le2 = 00 00 -> 65,536 bytes
        let bytesMax: [UInt8] = [0x00, 0xB0, 0x00, 0x00, 0x00, 0x00, 0x00]
        let cmdMax = pcsc.parseAPDU(bytesMax)
        XCTAssertEqual(cmdMax.le, 65536)
        XCTAssertTrue(cmdMax.isExtended)
    }

    func testCase3EExtendedApdu() throws {
        // 300 bytes of data payload
        let payload = [UInt8](repeating: 0xAB, count: 300)
        var bytes: [UInt8] = [0x00, 0xD6, 0x00, 0x00, 0x00, 0x01, 0x2C] // 0x012C = 300
        bytes.append(contentsOf: payload)

        let cmd = pcsc.parseAPDU(bytes)
        XCTAssertEqual(cmd.cla, 0x00)
        XCTAssertEqual(cmd.ins, 0xD6)
        XCTAssertEqual(cmd.p1, 0x00)
        XCTAssertEqual(cmd.p2, 0x00)
        XCTAssertEqual(cmd.data?.count, 300)
        XCTAssertEqual(cmd.data?.bytes.first, 0xAB)
        XCTAssertNil(cmd.le)
        XCTAssertTrue(cmd.isExtended)
    }

    func testCase4EExtendedApdu() throws {
        // 300 bytes of data payload + 2 bytes Le = 256 (0x0100)
        let payload = [UInt8](repeating: 0xCD, count: 300)
        var bytes: [UInt8] = [0x00, 0xD6, 0x00, 0x00, 0x00, 0x01, 0x2C]
        bytes.append(contentsOf: payload)
        bytes.append(contentsOf: [0x01, 0x00]) // Le = 256

        let cmd = pcsc.parseAPDU(bytes)
        XCTAssertEqual(cmd.cla, 0x00)
        XCTAssertEqual(cmd.ins, 0xD6)
        XCTAssertEqual(cmd.data?.count, 300)
        XCTAssertEqual(cmd.le, 256)
        XCTAssertTrue(cmd.isExtended)
    }

    // MARK: - ISO 7816-4 Command Chaining Tests (> 254 Bytes)

    func testCommandChainingNoSplitNeeded() throws {
        // 254 bytes does not require chaining
        let data = Data(repeating: 0x55, count: 254)
        let chunks = Pcsc.splitForCommandChaining(cla: 0x00, ins: 0xD6, p1: 0x00, p2: 0x00, data: data, originalLe: 16, chunkSize: 254)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].cla, 0x00) // CLA bit 5 remains 0
        XCTAssertEqual(chunks[0].data?.count, 254)
        XCTAssertEqual(chunks[0].le, 16)
    }

    func testCommandChainingSplit255Bytes() throws {
        // 255 bytes with chunkSize 254 splits into 2 chunks (254 + 1)
        let data = Data(repeating: 0x55, count: 255)
        let chunks = Pcsc.splitForCommandChaining(cla: 0x00, ins: 0xD6, p1: 0x00, p2: 0x00, data: data, originalLe: nil, chunkSize: 254)

        XCTAssertEqual(chunks.count, 2)

        // Chunk 1: intermediate command, CLA bit 5 set (0x00 | 0x10 = 0x10)
        XCTAssertEqual(chunks[0].cla, 0x10)
        XCTAssertEqual(chunks[0].ins, 0xD6)
        XCTAssertEqual(chunks[0].data?.count, 254)
        XCTAssertNil(chunks[0].le)

        // Chunk 2: final command, CLA bit 5 cleared (0x00 & ~0x10 = 0x00)
        XCTAssertEqual(chunks[1].cla, 0x00)
        XCTAssertEqual(chunks[1].ins, 0xD6)
        XCTAssertEqual(chunks[1].data?.count, 1)
        XCTAssertNil(chunks[1].le)
    }

    func testCommandChainingSplit500BytesWithLe() throws {
        // 500 bytes with chunkSize 254 splits into 2 chunks (254 + 246)
        let data = Data(repeating: 0xAA, count: 500)
        let chunks = Pcsc.splitForCommandChaining(cla: 0x00, ins: 0xD6, p1: 0x00, p2: 0x00, data: data, originalLe: 256, chunkSize: 254)

        XCTAssertEqual(chunks.count, 2)

        // Chunk 1
        XCTAssertEqual(chunks[0].cla, 0x10)
        XCTAssertEqual(chunks[0].data?.count, 254)
        XCTAssertNil(chunks[0].le) // Intermediate blocks do not have Le

        // Chunk 2 (Final)
        XCTAssertEqual(chunks[1].cla, 0x00)
        XCTAssertEqual(chunks[1].data?.count, 246)
        XCTAssertEqual(chunks[1].le, 256) // Final block carries original Le
    }

    func testCommandChainingSplit800BytesMultiBlock() throws {
        // 800 bytes splits into 4 chunks (254, 254, 254, 38)
        let data = Data(repeating: 0xEE, count: 800)
        let chunks = Pcsc.splitForCommandChaining(cla: 0x80, ins: 0xE2, p1: 0x00, p2: 0x00, data: data, originalLe: nil, chunkSize: 254)

        XCTAssertEqual(chunks.count, 4)
        // 0x80 | 0x10 = 0x90
        XCTAssertEqual(chunks[0].cla, 0x90)
        XCTAssertEqual(chunks[0].data?.count, 254)

        XCTAssertEqual(chunks[1].cla, 0x90)
        XCTAssertEqual(chunks[1].data?.count, 254)

        XCTAssertEqual(chunks[2].cla, 0x90)
        XCTAssertEqual(chunks[2].data?.count, 254)

        // Final chunk: 0x80 & ~0x10 = 0x80
        XCTAssertEqual(chunks[3].cla, 0x80)
        XCTAssertEqual(chunks[3].data?.count, 38)
    }

    // MARK: - ApduCommand Raw Serialization Tests

    func testRawBytesSerializationShort() throws {
        let cmd = ApduCommand(cla: 0x00, ins: 0xA4, p1: 0x04, p2: 0x00, data: Data([0x3F, 0x00]), le: 16)
        let raw = cmd.rawBytes
        XCTAssertEqual(raw, [0x00, 0xA4, 0x04, 0x00, 0x02, 0x3F, 0x00, 0x10])
    }

    func testRawBytesSerializationExtended() throws {
        let payload = Data(repeating: 0x01, count: 300)
        let cmd = ApduCommand(cla: 0x00, ins: 0xD6, p1: 0x00, p2: 0x00, data: payload, le: 256, isExtended: true)
        let raw = cmd.rawBytes
        XCTAssertEqual(raw[0...3], [0x00, 0xD6, 0x00, 0x00])
        XCTAssertEqual(raw[4], 0x00) // Extended prefix
        XCTAssertEqual(raw[5], 0x01) // Lc high
        XCTAssertEqual(raw[6], 0x2C) // Lc low = 300
        XCTAssertEqual(raw.count, 4 + 3 + 300 + 2) // Header 4 + Ext Lc 3 + Data 300 + Ext Le 2
    }
}
