//
//  PcscViewModel.swift
//  ApduTool
//
//  Created by Ken Cheung on 1/30/23.
//

import Foundation
import CryptoTokenKit

class PcscViewModel: ObservableObject {
    enum CardState: String {
        case unknown = "Unknown"
        case missing = "Missing"
        case empty = "Removed"
        case validCard = "Present"
        case muteCard = "Muted"
        case probing = "Probing"
    }
    @Published var selectedReader: String = ""
    @Published var slotNames:[String] = [String]()
    @Published var connected: Bool = false
    @Published var sendData: String = ""
    @Published var recvData: String = ""
    @Published var status: String = ""
    @Published var cardState: CardState = CardState.unknown
    var apdu: Apdu = Apdu()
    var pcsc: Pcsc = Pcsc()
    
    init() {
        slotNames = pcsc.getSlotNames()
        pcsc.setUpdateCardSlots(self.updateCardSlots)
        pcsc.setGetConnectResponse(self.getConnectResponse)
        pcsc.setGetTransmitResponse(self.getTransmitResponse)
        pcsc.setGetCardState(self.getCardState)
    }
    
    func updateCardSlots(manager: TKSmartCardSlotManager, change: NSKeyValueObservedChange<[String]>) {
        DispatchQueue.main.async { [unowned self] in
            self.slotNames = self.pcsc.getSlotNames()
            if self.connected && !self.slotNames.contains(self.selectedReader) {
                self.disconnect()
            }
        }
    }
    
    func getConnectResponse(res: Bool) {
        DispatchQueue.main.async { [unowned self] in
            self.connected = res
        }
    }
    
    func getTransmitResponse(data: Data?, error: Error?) {
        DispatchQueue.main.async { [unowned self] in
            self.apdu.recvData = data?.bytes ?? []
            if (error != nil) {
                self.status = error.debugDescription
            }
            self.recvData = self.apdu.recvData.hexString
        }
    }
    
    func getCardState(state: TKSmartCardSlot.State?) {
        DispatchQueue.main.async { [unowned self] in
            if (state != nil) {
                switch(state!) {
                case .missing:
                    self.cardState = CardState.unknown
                case .empty:
                    self.cardState = CardState.empty
                case .validCard:
                    self.cardState = CardState.validCard
                case .muteCard:
                    self.cardState = CardState.muteCard
                case .probing:
                    self.cardState = CardState.probing
                default:
                    self.cardState = CardState.unknown
                }
            } else {
                self.cardState = CardState.unknown
            }
        }
    }
    
    func transferApdu() {
        apdu.sendData = sendData.hexBytes
        recvData = ""
        status = ""
        pcsc.transferApdu(data: Data(apdu.sendData))
    }
    
    func connect() {
        status = ""
        pcsc.monitorSlot(readerName: selectedReader)
    }
    
    func disconnect() {
        pcsc.disconnect()
        connected = false
        cardState = CardState.unknown
    }
}
