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

    private func divideAPDU(_ apdu: [UInt8]) -> (cla: UInt8, ins: UInt8, p1: UInt8, p2: UInt8, data: Data?, le: Int?) {
        // Extract INS, CLA, P1, P2, and LE from APDU
        let cla = apdu[0]
        let ins = apdu[1]
        let p1 = apdu[2]
        let p2 = apdu[3]
        var lc: Int = 0
        var data: Data?
        var le: Int?
        var extendedApdu: Bool = false

        if apdu.count > 4 {
            lc = Int(apdu[4])
            extendedApdu = lc == 0
            let dataOffset = extendedApdu ? 7 : 5
            if apdu.count > dataOffset {
                if extendedApdu {
                    lc = (Int(apdu[5]) << 8) + Int(apdu[6])
                }
                if apdu.count >= dataOffset + lc {
                    data = Data(Array(apdu[dataOffset..<(dataOffset + lc)]))
                    if apdu.count > dataOffset + lc + (extendedApdu ? 1 : 0) {
                        let leOffset = dataOffset + lc
                        if extendedApdu { // Case 4E
                            le = (Int(apdu[leOffset]) << 8) + Int(apdu[leOffset + 1])
                        } else { // Case 4S
                            le = Int(apdu[leOffset])
                        }
                    } // else Case 3S or 3E
                }
            }
            else if apdu.count == dataOffset {
                let leOffset = dataOffset - (extendedApdu ? 2 : 1)
                if extendedApdu { // Case 2E
                    le = (Int(apdu[leOffset]) << 8) + Int(apdu[leOffset + 1])
                } else { // Case 2S
                    le = Int(apdu[leOffset])
                }
            }
        } // else Case 1
        return (cla, ins, p1, p2, data, le)
    }

    public func transferApdu(data: Data, getResponse: ((Data?, Error?) -> Void)?) {
        if activeCard != nil {
            guard data.count >= 4 else {
                let SCARD_E_INVALID_PARAMETER = 0x80100004
                let error = NSError(domain: "", code: SCARD_E_INVALID_PARAMETER, userInfo: [NSLocalizedDescriptionKey : "Invalid parameter"])
                getResponse?(nil, error)
                return
            }
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
                    // Extract SW1 and SW2 from the status word
                    let sw1: UInt8 = UInt8(sw >> 8 & 0xFF)
                    let sw2: UInt8 = UInt8(sw & 0xFF)
                    // Combine the reply data and status word into a single Data object
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
        } else {
            let SCARD_E_NO_SMARTCARD = 0x8010000C
            let error = NSError(domain: "", code: SCARD_E_NO_SMARTCARD, userInfo: [NSLocalizedDescriptionKey : "No active Card connection"])
            getResponse?(nil, error)
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
