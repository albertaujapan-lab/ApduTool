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
    
    struct CardInfo {
        var atr: String = ""
        var currentProtocol: String = ""
        var cardState: CardState = CardState.unknown
    }
    @Published var selectedReader: String = ""
    @Published var slotNames:[String] = []
    @Published var connected: Bool = false
    @Published var sendData: String = ""
    @Published var recvData: String = ""
    @Published var status: String = ""
    @Published var cardInfo: CardInfo = CardInfo()
    var apdu: Apdu = Apdu()
    var pcsc: Pcsc = Pcsc()
    
    init() {
        slotNames = pcsc.getSlotNames()
        pcsc.setUpdateCardSlots(self.updateCardSlots)
        pcsc.setGetConnectResponse(self.getConnectResponse)
        pcsc.setGetCardInfo(self.getCardInfo)
    }
    
    func updateCardSlots(manager: TKSmartCardSlotManager, change: NSKeyValueObservedChange<[String]>) {
        DispatchQueue.main.async { [unowned self] in
            slotNames = pcsc.getSlotNames()
            if connected && !slotNames.contains(selectedReader) {
                disconnect()
            }
        }
    }
    
    func getConnectResponse(res: Bool) {
        DispatchQueue.main.async { [unowned self] in
            connected = res
        }
    }
    
    func getResponse(data: Data?, error: Error?) {
        DispatchQueue.main.async { [unowned self] in
            apdu.recvData = data?.bytes ?? []
            if (error != nil) {
                status = error.debugDescription
            }
            recvData = apdu.recvData.hexString
        }
    }
    
    private func getProtocolString(_ cardProtocol: TKSmartCardProtocol) -> String {
        switch(cardProtocol) {
        case TKSmartCardProtocol.t0:
            return "T0"
        case TKSmartCardProtocol.t1:
            return "T1"
        case TKSmartCardProtocol.t15:
            return "T15"
        default:
            return "Any"
        }
    }
    
    func getCardInfo(state: TKSmartCardSlot.State?, error: Error?) {
        DispatchQueue.main.async { [unowned self] in
            if (state != nil) {
                switch(state!) {
                case .missing:
                    cardInfo = CardInfo()
                case .empty:
                    cardInfo = CardInfo(cardState: CardState.empty)
                case .validCard:
                    cardInfo.cardState = CardState.validCard
                    cardInfo.atr = pcsc.getAtr()
                    cardInfo.currentProtocol = getProtocolString(pcsc.getCurrentProtocol())
                case .muteCard:
                    cardInfo = CardInfo(cardState: CardState.muteCard)
                case .probing:
                    cardInfo = CardInfo(cardState: CardState.probing)
                default:
                    cardInfo = CardInfo()
                }
            } else {
                cardInfo = CardInfo()
            }
            if (error != nil) {
                status = error.debugDescription
            }
        }
    }
    
    func transferApdu() {
        apdu.sendData = sendData.hexBytes
        recvData = ""
        status = ""
        pcsc.transferApdu(data: Data(apdu.sendData), getResponse: getResponse)
    }
    
    func transferEscapeCommand() {
        apdu.sendData = sendData.hexBytes
        recvData = ""
        status = ""
        pcsc.transferEscapeCommand(readerName: selectedReader, data: Data(apdu.sendData), getResponse: getResponse)
    }
    
    func connect() {
        status = ""
        pcsc.monitorSlot(readerName: selectedReader)
    }
    
    func disconnect() {
        pcsc.disconnect()
        connected = false
        cardInfo = CardInfo()
    }
}
