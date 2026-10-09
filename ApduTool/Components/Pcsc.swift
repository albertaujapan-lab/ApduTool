//
//  Pcsc.swift
//  TestMacOS
//
//  Created by Ken Cheung on 1/26/23.
//

import Foundation
import CryptoTokenKit

class Pcsc : NSObject
{
    @objc private var mngr = TKSmartCardSlotManager.default
    private var managerObservation: NSKeyValueObservation?
    private var slotObservation: NSKeyValueObservation?
    private var activeCard: TKSmartCard? = nil
    private var currentSlot: TKSmartCardSlot? = nil
    private var escapeCommand: EscapeCommand = EscapeCommand()
#if os(macOS)
    private var transmitCommand: TransmitCommand = TransmitCommand()
#endif
    var updateCardSlots: ((TKSmartCardSlotManager, NSKeyValueObservedChange<[String]>) -> Void)?
    var getConnectResponse: ((Bool) -> Void)?
    var getCardInfo: ((TKSmartCardSlot.State?, Error?) -> Void)?
    var tpduReader: Bool = false
    public var autoIsoHandling: Bool = true
    public var onLogMessage: ((String) -> Void)?

    override init() {
        super.init()
        managerObservation = mngr?.observe(\.slotNames, options: .initial, changeHandler: updateCardSlots)
    }

    func setUpdateCardSlots(_ function: @escaping (TKSmartCardSlotManager, NSKeyValueObservedChange<[String]>) -> Void) {
        updateCardSlots = function
    }

    func getSlotNames() -> [String] {
        return mngr?.slotNames.filter({ name in
            return name.starts(with: "ACS")
        }) ?? []
    }

    func getAtr() -> String {
        return currentSlot?.atr?.bytes.bytes.hexString ?? ""
    }

    func getCurrentProtocol() -> TKSmartCardProtocol {
        return activeCard?.currentProtocol ?? TKSmartCardProtocol.any
    }

    private func updateCardSlots(manager: TKSmartCardSlotManager, change: NSKeyValueObservedChange<[String]>) {
        updateCardSlots?(manager, change)
    }

    private func isTPDUReader() -> Bool {
        if let readerName = currentSlot?.name {
            return readerName.contains("ACR40") || readerName.contains("ACR39") || readerName.contains("ACR38") ||
            readerName.contains("ACM40") || readerName.contains("ACM39") || readerName.contains("ACM38")
        } else {
            return false
        }
    }

    private func monitorCard() -> NSKeyValueObservation? {
        return self.currentSlot?.observe(\.state, options: .initial) { _, _ in
            if let state = self.currentSlot?.state {
                switch state {
                case .missing:
                    self.stopSlotMonitor()
                    self.getConnectResponse?(self.slotObservation != nil)
                case .empty:
                    self.activeCard?.endSession()
                    self.activeCard = nil
                case .validCard:
                    self.tpduReader = self.isTPDUReader()
                    self.activeCard = self.currentSlot?.makeSmartCard()
                    self.activeCard?.beginSession(reply: { res, error in
                        if (error != nil) {
                            self.activeCard = nil
                        }
                        self.getCardInfo?(state, error)
                    })
                    return
                default:
                    break
                }
                self.getCardInfo?(state, nil)
            } else {
                self.getCardInfo?(nil, nil)
            }
        }
    }

    public func startSlotMonitor(readerName: String, getConnectResponse: @escaping((Bool) -> Void), getCardInfo: @escaping((TKSmartCardSlot.State?, Error?) -> Void)) {
        self.getConnectResponse = getConnectResponse
        self.getCardInfo = getCardInfo
        _ = mngr?.getSlot(withName: readerName) { slot in
            self.currentSlot = slot
            self.slotObservation = self.monitorCard()
            self.getConnectResponse?(self.slotObservation != nil)
        }
    }

    public func stopSlotMonitor() {
        if activeCard != nil {
            activeCard?.endSession()
            activeCard = nil
        }
        if slotObservation != nil {
            slotObservation = nil
        }
    }

    public func resetCard(completion: @escaping (Result<[UInt8], Error>) -> Void) {
        guard let slot = currentSlot else {
            let SCARD_E_NO_SMARTCARD = 0x8010000C
            let error = NSError(domain: "", code: SCARD_E_NO_SMARTCARD, userInfo: [NSLocalizedDescriptionKey : "No active Card connection"])
            completion(.failure(error))
            return
        }
        
        // 1. Disconnect and end existing card session
        if let card = activeCard {
            card.endSession()
            activeCard = nil
        }
        
        // 2. Re-connect to the card with Warm Reset
        guard let newCard = slot.makeSmartCard() else {
            let SCARD_E_NO_SMARTCARD = 0x8010000C
            let error = NSError(domain: "", code: SCARD_E_NO_SMARTCARD, userInfo: [NSLocalizedDescriptionKey : "Failed to connect to card"])
            completion(.failure(error))
            return
        }
        
        // Setting isSensitive = true instructs CryptoTokenKit to execute a Warm Reset
        // (toggling the RST line while maintaining VCC) before starting the session.
        newCard.isSensitive = true
        
        newCard.beginSession { [weak self] res, error in
            guard let self = self else { return }
            if let error = error {
                self.activeCard = nil
                completion(.failure(error))
                return
            }
            // Reset isSensitive back to false so subsequent APDU transmissions do not re-trigger resets
            newCard.isSensitive = false
            self.activeCard = newCard
            self.tpduReader = self.isTPDUReader()
            
            // 3. Obtain the new ATR bytes
            let atrBytes: [UInt8] = slot.atr?.bytes.bytes ?? []
            completion(.success(atrBytes))
        }
    }

    public func divideAPDU(_ apdu: [UInt8]) -> (cla: UInt8, ins: UInt8, p1: UInt8, p2: UInt8, data: Data?, le: Int?) {
        let cmd = parseAPDU(apdu)
        return (cmd.cla, cmd.ins, cmd.p1, cmd.p2, cmd.data, cmd.le)
    }

    public func parseAPDU(_ apdu: [UInt8]) -> ApduCommand {
        guard apdu.count >= 4 else {
            return ApduCommand(cla: 0, ins: 0, p1: 0, p2: 0)
        }
        let cla = apdu[0]
        let ins = apdu[1]
        let p1 = apdu[2]
        let p2 = apdu[3]

        // Case 1: Exactly 4 bytes
        if apdu.count == 4 {
            return ApduCommand(cla: cla, ins: ins, p1: p1, p2: p2, data: nil, le: nil, isExtended: false)
        }

        // Case 2S: Exactly 5 bytes (Header + short Le)
        if apdu.count == 5 {
            let leByte = apdu[4]
            let le = (leByte == 0) ? 256 : Int(leByte)
            return ApduCommand(cla: cla, ins: ins, p1: p1, p2: p2, data: nil, le: le, isExtended: false)
        }

        // Extended APDU check: apdu[4] == 0x00 and apdu.count >= 7
        if apdu[4] == 0 && apdu.count >= 7 {
            let extVal = (Int(apdu[5]) << 8) | Int(apdu[6])

            // Case 2E: Exactly 7 bytes (Header + 00 + 2-byte Le)
            if apdu.count == 7 {
                let le = (extVal == 0) ? 65536 : extVal
                return ApduCommand(cla: cla, ins: ins, p1: p1, p2: p2, data: nil, le: le, isExtended: true)
            }

            // Case 3E: Exactly 7 + extVal bytes (Header + 00 + 2-byte Lc + Data)
            if apdu.count == 7 + extVal && extVal > 0 {
                let data = Data(apdu[7..<(7 + extVal)])
                return ApduCommand(cla: cla, ins: ins, p1: p1, p2: p2, data: data, le: nil, isExtended: true)
            }

            // Case 4E: Exactly 7 + extVal + 2 bytes (Header + 00 + 2-byte Lc + Data + 2-byte Le)
            if apdu.count == 7 + extVal + 2 && extVal > 0 {
                let data = Data(apdu[7..<(7 + extVal)])
                let leVal = (Int(apdu[7 + extVal]) << 8) | Int(apdu[7 + extVal + 1])
                let le = (leVal == 0) ? 65536 : leVal
                return ApduCommand(cla: cla, ins: ins, p1: p1, p2: p2, data: data, le: le, isExtended: true)
            }
        }

        // Short APDU check: apdu[4] is Lc
        let shortLc = Int(apdu[4])
        if shortLc > 0 && apdu.count >= 5 + shortLc {
            let data = Data(apdu[5..<(5 + shortLc)])
            if apdu.count == 5 + shortLc {
                // Case 3S: Header + Lc + Data
                return ApduCommand(cla: cla, ins: ins, p1: p1, p2: p2, data: data, le: nil, isExtended: false)
            } else if apdu.count == 5 + shortLc + 1 {
                // Case 4S: Header + Lc + Data + Le
                let leByte = apdu[5 + shortLc]
                let le = (leByte == 0) ? 256 : Int(leByte)
                return ApduCommand(cla: cla, ins: ins, p1: p1, p2: p2, data: data, le: le, isExtended: false)
            }
        }

        // Fallback for raw payload exceeding short Lc without extended prefix:
        if apdu.count > 5 {
            let data = Data(apdu[5...])
            return ApduCommand(cla: cla, ins: ins, p1: p1, p2: p2, data: data, le: nil, isExtended: false)
        }

        return ApduCommand(cla: cla, ins: ins, p1: p1, p2: p2, data: nil, le: nil, isExtended: false)
    }

    public static func splitForCommandChaining(
        cla: UInt8, ins: UInt8, p1: UInt8, p2: UInt8,
        data: Data, originalLe: Int? = nil,
        chunkSize: Int = 254
    ) -> [ApduCommand] {
        guard !data.isEmpty else {
            return [ApduCommand(cla: cla, ins: ins, p1: p1, p2: p2, data: nil, le: originalLe)]
        }
        
        let safeChunkSize = max(1, min(chunkSize, 255))
        if data.count <= safeChunkSize {
            return [ApduCommand(cla: cla, ins: ins, p1: p1, p2: p2, data: data, le: originalLe)]
        }
        
        // For transparent binary update/write commands, P1-P2 encodes the file offset
        let isBinaryUpdate = (ins == 0xD6 || ins == 0xD7 || ins == 0xD0 || ins == 0xD1)
        let isSfi = (p1 & 0x80) != 0
        let baseOffset = isSfi ? Int(p2) : ((Int(p1) << 8) | Int(p2))

        var commands: [ApduCommand] = []
        let totalCount = data.count
        var offset = 0
        
        while offset < totalCount {
            let remaining = totalCount - offset
            let thisChunkSize = min(remaining, safeChunkSize)
            let chunkData = data.subdata(in: offset..<(offset + thisChunkSize))
            let isLast = (offset + thisChunkSize >= totalCount)
            
            // ISO 7816-4: Bit 5 of CLA is 1 for intermediate commands, 0 for final command
            let chunkCla = isLast ? (cla & ~0x10) : (cla | 0x10)
            let chunkLe = isLast ? originalLe : nil
            
            var chunkP1 = p1
            var chunkP2 = p2
            if isBinaryUpdate {
                let currentOffset = baseOffset + offset
                if !isSfi {
                    chunkP1 = UInt8((currentOffset >> 8) & 0xFF)
                    chunkP2 = UInt8(currentOffset & 0xFF)
                } else {
                    chunkP1 = p1
                    chunkP2 = UInt8(currentOffset & 0xFF)
                }
            }
            
            commands.append(ApduCommand(cla: chunkCla, ins: ins, p1: chunkP1, p2: chunkP2, data: chunkData, le: chunkLe, isExtended: false))
            offset += thisChunkSize
        }
        
        return commands
    }

    public static func splitForSegmentedReadBinary(
        cla: UInt8, ins: UInt8, p1: UInt8, p2: UInt8,
        totalLe: Int,
        chunkSize: Int = 256
    ) -> [ApduCommand] {
        guard totalLe > 0 else { return [] }
        let safeChunkSize = max(1, min(chunkSize, 256))
        let isSfi = (p1 & 0x80) != 0
        let baseOffset = isSfi ? Int(p2) : ((Int(p1) << 8) | Int(p2))
        
        var commands: [ApduCommand] = []
        var bytesRead = 0
        
        while bytesRead < totalLe {
            let remaining = totalLe - bytesRead
            let thisChunkLe = min(remaining, safeChunkSize)
            let currentOffset = baseOffset + bytesRead
            
            let chunkP1: UInt8
            let chunkP2: UInt8
            if !isSfi {
                chunkP1 = UInt8((currentOffset >> 8) & 0xFF)
                chunkP2 = UInt8(currentOffset & 0xFF)
            } else {
                chunkP1 = p1
                chunkP2 = UInt8(currentOffset & 0xFF)
            }
            
            commands.append(
                ApduCommand(
                    cla: cla,
                    ins: ins,
                    p1: chunkP1,
                    p2: chunkP2,
                    data: nil,
                    le: thisChunkLe,
                    isExtended: false
                )
            )
            bytesRead += thisChunkLe
        }
        return commands
    }

#if os(macOS)
    private func transmitTpduMac(readerName: String, data: Data, completion: @escaping (Data?, Error?) -> Void) {
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.activeCard?.endSession()
            self.transmitCommand(readerName: readerName, data: data, getResponse: completion)
            self.activeCard?.beginSession(reply: { res, error in
                if error != nil {
                    self.activeCard = nil
                }
                semaphore.signal()
            })
        }
        _ = semaphore.wait(timeout: .now() + 10.0)
    }
#endif

    private func sendSingleAPDU(
        cla: UInt8, ins: UInt8, p1: UInt8, p2: UInt8,
        data: Data?, le: Int?,
        getResponse: @escaping (Data?, UInt16, Error?) -> Void
    ) {
        guard let card = activeCard else {
            let SCARD_E_NO_SMARTCARD = 0x8010000C
            let error = NSError(domain: "", code: SCARD_E_NO_SMARTCARD, userInfo: [NSLocalizedDescriptionKey : "No active Card connection"])
            getResponse(nil, 0, error)
            return
        }

#if os(macOS)
        if tpduReader, let readerName = card.slot.name {
            var rawBytes: [UInt8] = [cla, ins, p1, p2]
            if let data = data, !data.isEmpty {
                rawBytes.append(UInt8(data.count & 0xFF))
                rawBytes.append(contentsOf: [UInt8](data))
            }
            if let le = le {
                let leByte = (le == 256) ? 0 : UInt8(le & 0xFF)
                rawBytes.append(leByte)
            }
            transmitTpduMac(readerName: readerName, data: Data(rawBytes)) { resData, error in
                if let error = error {
                    getResponse(nil, 0, error)
                    return
                }
                guard let resData = resData, resData.count >= 2 else {
                    getResponse(resData, 0, nil)
                    return
                }
                let count = resData.count
                let sw1 = resData[count - 2]
                let sw2 = resData[count - 1]
                let sw = (UInt16(sw1) << 8) | UInt16(sw2)
                let reply = count > 2 ? resData.subdata(in: 0..<(count - 2)) : Data()
                getResponse(reply, sw, nil)
            }
            return
        }
#endif

        card.cla = cla
        card.useExtendedLength = true
        card.useCommandChaining = false
        card.send(ins: ins, p1: p1, p2: p2, data: data, le: le) { replyData, sw, error in
            getResponse(replyData, sw, error)
        }
    }

    private func executeIsoApdu(
        command: ApduCommand,
        getResponse: @escaping (Data?, Error?) -> Void
    ) {
        let dataPayload = command.data ?? Data()
        
        // 1. If data payload exceeds standard block size (254 bytes), perform ISO 7816-4 command chaining
        if dataPayload.count > 254 {
            let chunks = Pcsc.splitForCommandChaining(
                cla: command.cla,
                ins: command.ins,
                p1: command.p1,
                p2: command.p2,
                data: dataPayload,
                originalLe: command.le,
                chunkSize: 254
            )
            
            executeChainedCommands(chunks: chunks, index: 0) { [weak self] finalReply, finalSW, error in
                guard let self = self else { return }
                if let error = error {
                    getResponse(nil, error)
                    return
                }
                self.handleIsoResponse(
                    initialReply: finalReply ?? Data(),
                    sw: finalSW,
                    originalCommand: chunks.last ?? command,
                    iteration: 0,
                    completion: getResponse
                )
            }
            return
        }
        
        // 2. If READ BINARY requests Le > 256 bytes, perform automated segmented reading
        let isBinaryRead = (command.ins == 0xB0 || command.ins == 0xB1) && (command.data == nil || command.data!.isEmpty)
        if isBinaryRead, let requestedLe = command.le, requestedLe > 256 {
            executeSegmentedReadBinary(command: command, totalLe: requestedLe, chunkSize: 256, completion: getResponse)
            return
        }
        
        // 3. Otherwise, send single APDU and handle 61 XX / 6C XX procedure responses
        sendSingleAPDU(
            cla: command.cla,
            ins: command.ins,
            p1: command.p1,
            p2: command.p2,
            data: command.data,
            le: command.le
        ) { [weak self] replyData, sw, error in
            guard let self = self else { return }
            if let error = error {
                getResponse(nil, error)
                return
            }
            self.handleIsoResponse(
                initialReply: replyData ?? Data(),
                sw: sw,
                originalCommand: command,
                iteration: 0,
                completion: getResponse
            )
        }
    }

    private func executeSegmentedReadBinary(
        command: ApduCommand,
        totalLe: Int,
        chunkSize: Int = 256,
        completion: @escaping (Data?, Error?) -> Void
    ) {
        let chunks = Pcsc.splitForSegmentedReadBinary(
            cla: command.cla,
            ins: command.ins,
            p1: command.p1,
            p2: command.p2,
            totalLe: totalLe,
            chunkSize: chunkSize
        )
        executeReadBinaryChunks(chunks: chunks, index: 0, accumulated: Data(), completion: completion)
    }

    private func executeReadBinaryChunks(
        chunks: [ApduCommand],
        index: Int,
        accumulated: Data,
        completion: @escaping (Data?, Error?) -> Void
    ) {
        guard index < chunks.count else {
            var finalData = accumulated
            finalData.append(0x90)
            finalData.append(0x00)
            completion(finalData, nil)
            return
        }
        
        let chunk = chunks[index]
        let rawHex = chunk.rawBytes.hexString
        onLogMessage?("[Read \(index + 1)/\(chunks.count)] \(rawHex)")
        
        sendSingleAPDU(
            cla: chunk.cla,
            ins: chunk.ins,
            p1: chunk.p1,
            p2: chunk.p2,
            data: chunk.data,
            le: chunk.le
        ) { [weak self] replyData, sw, error in
            guard let self = self else { return }
            if let error = error {
                var failData = accumulated
                if let data = replyData { failData.append(data) }
                failData.append(UInt8(sw >> 8 & 0xFF))
                failData.append(UInt8(sw & 0xFF))
                completion(failData, error)
                return
            }
            
            let sw1 = UInt8(sw >> 8 & 0xFF)
            let sw2 = UInt8(sw & 0xFF)
            
            // 1. T=0 Procedure: Response bytes available (61 XX)
            if sw1 == 0x61 {
                let bytesToFetch = (sw2 == 0) ? 256 : Int(sw2)
                self.sendSingleAPDU(cla: 0x00, ins: 0xC0, p1: 0x00, p2: 0x00, data: nil, le: bytesToFetch) { [weak self] grData, grSW, grErr in
                    guard let self = self else { return }
                    if let grErr = grErr {
                        var failData = accumulated
                        failData.append(sw1)
                        failData.append(sw2)
                        completion(failData, grErr)
                        return
                    }
                    var nextAccum = accumulated
                    if let data = grData { nextAccum.append(data) }
                    if grSW == 0x9000 {
                        self.executeReadBinaryChunks(chunks: chunks, index: index + 1, accumulated: nextAccum, completion: completion)
                    } else {
                        nextAccum.append(UInt8(grSW >> 8 & 0xFF))
                        nextAccum.append(UInt8(grSW & 0xFF))
                        completion(nextAccum, nil)
                    }
                }
                return
            }
            
            // 2. Wrong Le length (6C XX)
            if sw1 == 0x6C {
                let reLe = (sw2 == 0) ? 256 : Int(sw2)
                self.sendSingleAPDU(
                    cla: chunk.cla,
                    ins: chunk.ins,
                    p1: chunk.p1,
                    p2: chunk.p2,
                    data: chunk.data,
                    le: reLe
                ) { [weak self] reReply, reSW, reErr in
                    guard let self = self else { return }
                    if let reErr = reErr {
                        var failData = accumulated
                        failData.append(UInt8(reSW >> 8 & 0xFF))
                        failData.append(UInt8(reSW & 0xFF))
                        completion(failData, reErr)
                        return
                    }
                    var nextAccum = accumulated
                    if let data = reReply { nextAccum.append(data) }
                    if reSW == 0x9000 {
                        self.executeReadBinaryChunks(chunks: chunks, index: index + 1, accumulated: nextAccum, completion: completion)
                    } else {
                        nextAccum.append(UInt8(reSW >> 8 & 0xFF))
                        nextAccum.append(UInt8(reSW & 0xFF))
                        completion(nextAccum, nil)
                    }
                }
                return
            }
            
            var nextAccum = accumulated
            if let data = replyData { nextAccum.append(data) }
            
            // 3. Normal success
            if sw == 0x9000 {
                let expectedChunkLen = chunk.le ?? 256
                if let data = replyData, data.count < expectedChunkLen {
                    // Reached end of file early
                    var finalData = nextAccum
                    finalData.append(0x90)
                    finalData.append(0x00)
                    completion(finalData, nil)
                    return
                }
                self.executeReadBinaryChunks(chunks: chunks, index: index + 1, accumulated: nextAccum, completion: completion)
            } else if sw == 0x6282 {
                // End of file reached
                var finalData = nextAccum
                finalData.append(0x90)
                finalData.append(0x00)
                completion(finalData, nil)
            } else {
                nextAccum.append(sw1)
                nextAccum.append(sw2)
                completion(nextAccum, nil)
            }
        }
    }

    private func executeChainedCommands(
        chunks: [ApduCommand],
        index: Int,
        completion: @escaping (Data?, UInt16, Error?) -> Void
    ) {
        guard index < chunks.count else {
            completion(nil, 0x9000, nil)
            return
        }
        
        let chunk = chunks[index]
        let isLast = (index == chunks.count - 1)
        
        if chunks.count > 1 {
            let hexStr = chunk.rawBytes.hexString
            onLogMessage?("[Chain \(index + 1)/\(chunks.count)] \(hexStr)")
        }
        
        sendSingleAPDU(
            cla: chunk.cla,
            ins: chunk.ins,
            p1: chunk.p1,
            p2: chunk.p2,
            data: chunk.data,
            le: chunk.le
        ) { [weak self] replyData, sw, error in
            guard let self = self else { return }
            if let error = error {
                completion(nil, sw, error)
                return
            }
            
            if !isLast {
                // Intermediate command must return 9000 (or procedure)
                if sw != 0x9000 {
                    let err = NSError(
                        domain: "ISO7816Chaining",
                        code: Int(sw),
                        userInfo: [NSLocalizedDescriptionKey: "Chaining rejected at block \(index + 1) with SW: \(String(format: "%04X", sw))"]
                    )
                    var failData = replyData ?? Data()
                    failData.append(UInt8(sw >> 8 & 0xFF))
                    failData.append(UInt8(sw & 0xFF))
                    completion(failData, sw, err)
                    return
                }
                self.executeChainedCommands(chunks: chunks, index: index + 1, completion: completion)
            } else {
                completion(replyData, sw, nil)
            }
        }
    }

    private func handleIsoResponse(
        initialReply: Data,
        sw: UInt16,
        originalCommand: ApduCommand,
        iteration: Int,
        completion: @escaping (Data?, Error?) -> Void
    ) {
        var accumulated = initialReply
        let sw1 = UInt8(sw >> 8 & 0xFF)
        let sw2 = UInt8(sw & 0xFF)
        
        // Safeguard to prevent endless loops
        if iteration > 100 {
            accumulated.append(sw1)
            accumulated.append(sw2)
            completion(accumulated, nil)
            return
        }
        
        // 1. T=0 Procedure / Response bytes available (SW1 == 0x61)
        if sw1 == 0x61 {
            let bytesToFetch = (sw2 == 0) ? 256 : Int(sw2)
            onLogMessage?("[Auto GET RESPONSE] 00C00000\(String(format: "%02X", sw2)) (\(bytesToFetch) bytes)")
            
            sendSingleAPDU(cla: 0x00, ins: 0xC0, p1: 0x00, p2: 0x00, data: nil, le: bytesToFetch) { [weak self] replyData, nextSW, error in
                guard let self = self else { return }
                if let error = error {
                    accumulated.append(sw1)
                    accumulated.append(sw2)
                    completion(accumulated, error)
                    return
                }
                if let data = replyData {
                    accumulated.append(data)
                }
                self.handleIsoResponse(
                    initialReply: accumulated,
                    sw: nextSW,
                    originalCommand: originalCommand,
                    iteration: iteration + 1,
                    completion: completion
                )
            }
            return
        }
        
        // 2. Wrong Le length (SW1 == 0x6C)
        if sw1 == 0x6C {
            let correctLe = (sw2 == 0) ? 256 : Int(sw2)
            onLogMessage?("[Auto Reissue with Le=\(correctLe)]")
            
            sendSingleAPDU(
                cla: originalCommand.cla,
                ins: originalCommand.ins,
                p1: originalCommand.p1,
                p2: originalCommand.p2,
                data: originalCommand.data,
                le: correctLe
            ) { [weak self] reReply, reSW, error in
                guard let self = self else { return }
                if let error = error {
                    completion(nil, error)
                    return
                }
                self.handleIsoResponse(
                    initialReply: reReply ?? Data(),
                    sw: reSW,
                    originalCommand: originalCommand,
                    iteration: iteration + 1,
                    completion: completion
                )
            }
            return
        }
        
        // 3. Normal / Final status word
        accumulated.append(sw1)
        accumulated.append(sw2)
        completion(accumulated, nil)
    }

    public func transferApdu(data: Data, autoIsoHandling: Bool? = nil, getResponse: ((Data?, Error?) -> Void)?) {
        guard activeCard != nil else {
            let SCARD_E_NO_SMARTCARD = 0x8010000C
            let error = NSError(domain: "", code: SCARD_E_NO_SMARTCARD, userInfo: [NSLocalizedDescriptionKey : "No active Card connection"])
            getResponse?(nil, error)
            return
        }
        guard data.count >= 4 else {
            let SCARD_E_INVALID_PARAMETER = 0x80100004
            let error = NSError(domain: "", code: SCARD_E_INVALID_PARAMETER, userInfo: [NSLocalizedDescriptionKey : "Invalid parameter"])
            getResponse?(nil, error)
            return
        }

        let shouldAutoHandle = autoIsoHandling ?? self.autoIsoHandling
        if shouldAutoHandle {
            let cmd = parseAPDU(data.bytes)
            executeIsoApdu(command: cmd, getResponse: getResponse ?? { _, _ in })
        } else {
            // Raw / Manual Mode
            if tpduReader {
#if os(macOS)
                if let readerName = activeCard?.slot.name {
                    let semaphore = DispatchSemaphore(value: 0)
                    DispatchQueue.global(qos: .userInitiated).async { [self] in
                        activeCard?.endSession()
                        transmitCommand(readerName: readerName, data: data, getResponse: getResponse)
                        activeCard?.beginSession(reply: { res, error in
                            if (error != nil) {
                                self.activeCard = nil
                            }
                            semaphore.signal()
                        })
                    }
                    _ = semaphore.wait(timeout: .now() + 10.0)
                }
#else
                let (cla, ins, p1, p2, sendData, le) = divideAPDU(data.bytes)
                activeCard?.cla = cla
                activeCard?.useExtendedLength = true
                activeCard?.useCommandChaining = true
                activeCard?.send(ins: ins, p1: p1, p2: p2, data: sendData, le: le, reply: { replyData, sw, error in
                    let sw1: UInt8 = UInt8(sw >> 8 & 0xFF)
                    let sw2: UInt8 = UInt8(sw & 0xFF)
                    var responseData = Data()
                    responseData.append(replyData ?? Data())
                    responseData.append(Data([sw1, sw2]))
                    getResponse?(responseData, error)
                })
#endif
            } else {
                activeCard?.transmit(Data(data), reply: { data, error in
                    getResponse?(data, error)
                })
            }
        }
    }

    public func transferEscapeCommand(readerName: String, data: Data, getResponse: ((Data?, Error?) -> Void)?) {
        let szReader = (UnsafePointer<CChar>)(strdup(readerName)!)
        let sendData = (UnsafeMutablePointer<UInt8>)(mutating: NSData(bytes: data.bytes, length: data.count).bytes.assumingMemoryBound(to: UInt8.self))
        let recvData = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
        let pRecvLength = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        let result = escapeCommand.transfer(szReader, andSendData: sendData, andSendLength: (UInt32)(data.count), andRecvData: recvData, andPRecvLength: pRecvLength)
        if getResponse != nil {
            var error: Error? = nil
            let data = Data(buffer: UnsafeMutableBufferPointer(start: recvData, count: (Int)(pRecvLength.pointee)))
            if result != 0 {
                error = NSError(domain: "", code: Int(result), userInfo: [NSLocalizedDescriptionKey : "Escape command transfer failure"])
            }
            getResponse?(data, error)
        }
        recvData.deallocate()
        pRecvLength.deallocate()
        szReader.deallocate()
    }

#if os(macOS)
    public func transmitCommand(readerName: String, data: Data, getResponse: ((Data?, Error?) -> Void)?) {
        let szReader = (UnsafePointer<CChar>)(strdup(readerName)!)
        let sendData = (UnsafeMutablePointer<UInt8>)(mutating: NSData(bytes: data.bytes, length: data.count).bytes.assumingMemoryBound(to: UInt8.self))
        let recvData = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
        let pRecvLength = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        pRecvLength.pointee = 65536
        let result = transmitCommand.transfer(szReader, andSendData: sendData, andSendLength: (UInt32)(data.count), andRecvData: recvData, andPRecvLength: pRecvLength)
        if getResponse != nil {
            var error: Error? = nil
            let data = Data(buffer: UnsafeMutableBufferPointer(start: recvData, count: (Int)(pRecvLength.pointee)))
            if result != 0 {
                error = NSError(domain: "", code: Int(result), userInfo: [NSLocalizedDescriptionKey : "Command transfer failure"])
            }
            getResponse?(data, error)
        }
        recvData.deallocate()
        pRecvLength.deallocate()
        szReader.deallocate()
    }
#endif
}
