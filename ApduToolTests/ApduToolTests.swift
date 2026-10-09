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

        // Chunk 1: intermediate command, CLA bit 5 set (0x00 | 0x10 = 0x10), offset 0
        XCTAssertEqual(chunks[0].cla, 0x10)
        XCTAssertEqual(chunks[0].ins, 0xD6)
        XCTAssertEqual(chunks[0].p1, 0x00)
        XCTAssertEqual(chunks[0].p2, 0x00)
        XCTAssertEqual(chunks[0].data?.count, 254)
        XCTAssertNil(chunks[0].le)

        // Chunk 2: final command, CLA bit 5 cleared (0x00 & ~0x10 = 0x00), offset 254 (0x00FE)
        XCTAssertEqual(chunks[1].cla, 0x00)
        XCTAssertEqual(chunks[1].ins, 0xD6)
        XCTAssertEqual(chunks[1].p1, 0x00)
        XCTAssertEqual(chunks[1].p2, 0xFE)
        XCTAssertEqual(chunks[1].data?.count, 1)
        XCTAssertNil(chunks[1].le)
    }

    func testCommandChainingSplit500BytesWithLe() throws {
        // 500 bytes with chunkSize 254 splits into 2 chunks (254 + 246)
        let data = Data(repeating: 0xAA, count: 500)
        let chunks = Pcsc.splitForCommandChaining(cla: 0x00, ins: 0xD6, p1: 0x00, p2: 0x00, data: data, originalLe: 256, chunkSize: 254)

        XCTAssertEqual(chunks.count, 2)

        // Chunk 1: offset 0
        XCTAssertEqual(chunks[0].cla, 0x10)
        XCTAssertEqual(chunks[0].p1, 0x00)
        XCTAssertEqual(chunks[0].p2, 0x00)
        XCTAssertEqual(chunks[0].data?.count, 254)
        XCTAssertNil(chunks[0].le)

        // Chunk 2 (Final): offset 254 (0x00FE)
        XCTAssertEqual(chunks[1].cla, 0x00)
        XCTAssertEqual(chunks[1].p1, 0x00)
        XCTAssertEqual(chunks[1].p2, 0xFE)
        XCTAssertEqual(chunks[1].data?.count, 246)
        XCTAssertEqual(chunks[1].le, 256)
    }

    func testCommandChainingSplit800BytesMultiBlock() throws {
        // 800 bytes splits into 4 chunks (254, 254, 254, 38)
        // For non-binary command (0xE2), P1-P2 are preserved as-is
        let data = Data(repeating: 0xEE, count: 800)
        let chunks = Pcsc.splitForCommandChaining(cla: 0x80, ins: 0xE2, p1: 0x00, p2: 0x00, data: data, originalLe: nil, chunkSize: 254)

        XCTAssertEqual(chunks.count, 4)
        // 0x80 | 0x10 = 0x90
        XCTAssertEqual(chunks[0].cla, 0x90)
        XCTAssertEqual(chunks[0].p1, 0x00)
        XCTAssertEqual(chunks[0].p2, 0x00)
        XCTAssertEqual(chunks[0].data?.count, 254)

        XCTAssertEqual(chunks[1].cla, 0x90)
        XCTAssertEqual(chunks[1].p1, 0x00)
        XCTAssertEqual(chunks[1].p2, 0x00)
        XCTAssertEqual(chunks[1].data?.count, 254)

        XCTAssertEqual(chunks[2].cla, 0x90)
        XCTAssertEqual(chunks[2].p1, 0x00)
        XCTAssertEqual(chunks[2].p2, 0x00)
        XCTAssertEqual(chunks[2].data?.count, 254)

        // Final chunk: 0x80 & ~0x10 = 0x80
        XCTAssertEqual(chunks[3].cla, 0x80)
        XCTAssertEqual(chunks[3].p1, 0x00)
        XCTAssertEqual(chunks[3].p2, 0x00)
        XCTAssertEqual(chunks[3].data?.count, 38)
    }

    func testCommandChaining4096BytesUpdateBinaryOffsets() throws {
        // 4096 bytes for UPDATE BINARY (0xD6) at offset 0
        // Splits into 17 chunks (16 * 254 = 4064 + 32)
        let data = Data(repeating: 0x42, count: 4096)
        let chunks = Pcsc.splitForCommandChaining(cla: 0x00, ins: 0xD6, p1: 0x00, p2: 0x00, data: data, originalLe: nil, chunkSize: 254)

        XCTAssertEqual(chunks.count, 17)

        // Chunk 0: offset 0 (0x0000)
        XCTAssertEqual(chunks[0].cla, 0x10)
        XCTAssertEqual(chunks[0].p1, 0x00)
        XCTAssertEqual(chunks[0].p2, 0x00)
        XCTAssertEqual(chunks[0].data?.count, 254)

        // Chunk 1: offset 254 (0x00FE)
        XCTAssertEqual(chunks[1].cla, 0x10)
        XCTAssertEqual(chunks[1].p1, 0x00)
        XCTAssertEqual(chunks[1].p2, 0xFE)
        XCTAssertEqual(chunks[1].data?.count, 254)

        // Chunk 2: offset 508 (0x01FC)
        XCTAssertEqual(chunks[2].cla, 0x10)
        XCTAssertEqual(chunks[2].p1, 0x01)
        XCTAssertEqual(chunks[2].p2, 0xFC)
        XCTAssertEqual(chunks[2].data?.count, 254)

        // Chunk 15: offset 3810 (0x0EE2)
        XCTAssertEqual(chunks[15].cla, 0x10)
        XCTAssertEqual(chunks[15].p1, 0x0E)
        XCTAssertEqual(chunks[15].p2, 0xE2)
        XCTAssertEqual(chunks[15].data?.count, 254)

        // Chunk 16 (Final): offset 4064 (0x0FE0), length 32
        XCTAssertEqual(chunks[16].cla, 0x00)
        XCTAssertEqual(chunks[16].p1, 0x0F)
        XCTAssertEqual(chunks[16].p2, 0xE0)
        XCTAssertEqual(chunks[16].data?.count, 32)
    }

    // MARK: - Segmented READ BINARY Tests

    func testSegmentedReadBinary4096Bytes() throws {
        // READ BINARY (0xB0) requesting 4096 bytes at offset 0
        // Splits into 16 chunks of 256 bytes
        let chunks = Pcsc.splitForSegmentedReadBinary(cla: 0x00, ins: 0xB0, p1: 0x00, p2: 0x00, totalLe: 4096, chunkSize: 256)

        XCTAssertEqual(chunks.count, 16)

        // Chunk 0: offset 0 (0x0000), Le 256
        XCTAssertEqual(chunks[0].cla, 0x00)
        XCTAssertEqual(chunks[0].ins, 0xB0)
        XCTAssertEqual(chunks[0].p1, 0x00)
        XCTAssertEqual(chunks[0].p2, 0x00)
        XCTAssertEqual(chunks[0].le, 256)
        XCTAssertEqual(chunks[0].rawBytes, [0x00, 0xB0, 0x00, 0x00, 0x00])

        // Chunk 1: offset 256 (0x0100), Le 256
        XCTAssertEqual(chunks[1].cla, 0x00)
        XCTAssertEqual(chunks[1].ins, 0xB0)
        XCTAssertEqual(chunks[1].p1, 0x01)
        XCTAssertEqual(chunks[1].p2, 0x00)
        XCTAssertEqual(chunks[1].le, 256)
        XCTAssertEqual(chunks[1].rawBytes, [0x00, 0xB0, 0x01, 0x00, 0x00])

        // Chunk 15: offset 3840 (0x0F00), Le 256
        XCTAssertEqual(chunks[15].cla, 0x00)
        XCTAssertEqual(chunks[15].ins, 0xB0)
        XCTAssertEqual(chunks[15].p1, 0x0F)
        XCTAssertEqual(chunks[15].p2, 0x00)
        XCTAssertEqual(chunks[15].le, 256)
        XCTAssertEqual(chunks[15].rawBytes, [0x00, 0xB0, 0x0F, 0x00, 0x00])
    }

    func testSegmentedReadBinary300Bytes() throws {
        // READ BINARY requesting 300 bytes (256 + 44)
        let chunks = Pcsc.splitForSegmentedReadBinary(cla: 0x00, ins: 0xB0, p1: 0x00, p2: 0x00, totalLe: 300, chunkSize: 256)

        XCTAssertEqual(chunks.count, 2)

        // Chunk 0: 256 bytes at offset 0
        XCTAssertEqual(chunks[0].p1, 0x00)
        XCTAssertEqual(chunks[0].p2, 0x00)
        XCTAssertEqual(chunks[0].le, 256)
        XCTAssertEqual(chunks[0].rawBytes, [0x00, 0xB0, 0x00, 0x00, 0x00])

        // Chunk 1: 44 bytes at offset 256 (0x0100)
        XCTAssertEqual(chunks[1].p1, 0x01)
        XCTAssertEqual(chunks[1].p2, 0x00)
        XCTAssertEqual(chunks[1].le, 44)
        XCTAssertEqual(chunks[1].rawBytes, [0x00, 0xB0, 0x01, 0x00, 0x2C])
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
