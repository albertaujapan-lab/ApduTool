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
    var updateCardSlots: ((TKSmartCardSlotManager, NSKeyValueObservedChange<[String]>) -> Void)?
    var getConnectResponse: ((Bool) -> Void)?
    var getCardInfo: ((TKSmartCardSlot.State?, Error?) -> Void)?
    
    override init() {
        super.init()
        managerObservation = mngr?.observe(\.slotNames, options: .initial, changeHandler: updateCardSlots)
    }
    
    func setUpdateCardSlots(_ function: @escaping (TKSmartCardSlotManager, NSKeyValueObservedChange<[String]>) -> Void) {
        updateCardSlots = function
    }
    
    func setGetConnectResponse(_ function: @escaping ((Bool) -> Void)) {
        getConnectResponse = function
    }
    
    func setGetCardInfo(_ function: @escaping((TKSmartCardSlot.State?, Error?) -> Void)) {
        getCardInfo = function
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
    
    public func monitorSlot(readerName: String) {
        _ = mngr?.getSlot(withName: readerName) { slot in
            self.currentSlot = slot
            self.slotObservation = self.currentSlot?.observe(\.state, options: .initial) { _, _ in
                if let state = self.currentSlot?.state {
                    switch state {
                    case .missing:
                        self.slotObservation = nil
                        self.activeCard?.endSession()
                        self.activeCard = nil
                    case .empty:
                        self.activeCard?.endSession()
                        self.activeCard = nil
                    case .validCard:
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
            self.getConnectResponse?(self.slotObservation != nil)
        }
    }
    
    public func disconnect() {
        if (activeCard != nil) {
            activeCard?.endSession()
            activeCard = nil
        }
        if (slotObservation != nil) {
            slotObservation = nil
        }
    }
    
    public func transferApdu(data: Data, getResponse: ((Data?, Error?) -> Void)?) {
        if (activeCard != nil) {
            activeCard?.transmit(Data(data), reply: { data, error in
                getResponse?(data, error)
            })
        }
    }
    
    public func transferEscapeCommand(readerName: String, data: Data, getResponse: ((Data?, Error?) -> Void)?) {
        let szReader = (UnsafePointer<CChar>)(strdup(readerName)!)
        let sendData = (UnsafeMutablePointer<UInt8>)(mutating: NSData(bytes: data.bytes, length: data.count).bytes.assumingMemoryBound(to: UInt8.self))
        let recvData = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
        let pRecvLength = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        escapeCommand.transfer(szReader, andSendData: sendData, andSendLength: (UInt32)(data.count), andRecvData: recvData, andPRecvLength: pRecvLength)
        if (getResponse != nil) {
            let data = Data(buffer: UnsafeMutableBufferPointer(start: recvData, count: (Int)(pRecvLength.pointee)))
            getResponse?(data, nil)
        }
    }
}
