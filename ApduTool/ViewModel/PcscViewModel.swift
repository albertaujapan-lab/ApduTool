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
    @Published var message: String = ""
    @Published var cardInfo: CardInfo = CardInfo()
    @Published var toastMessage: String = ""
    @Published var showToast: Bool = false
    @Published var processing = false
    var scriptFile: String = ""
    var lines: [String] = []
    var line: Int = 0
    var apdu: Apdu = Apdu()
    var pcsc: Pcsc = Pcsc()
    var script: Script = Script()
    
    init() {
        slotNames = pcsc.getSlotNames()
        pcsc.setUpdateCardSlots(self.updateCardSlots)
    }
    
    func addMessage(text: String) {
        DispatchQueue.main.async { [self] in
            if text != "" {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
                let timeStamp = dateFormatter.string(from: Date())
                message = message + "\(timeStamp): \(text)\n"
            } else {
                message = ""
            }
        }
    }
    
    func updateCardSlots(manager: TKSmartCardSlotManager, change: NSKeyValueObservedChange<[String]>) {
        DispatchQueue.main.async { [self] in
            slotNames = pcsc.getSlotNames()
        }
    }
    
    func getConnectResponse(res: Bool) {
        DispatchQueue.main.async { [self] in
            connected = res
            addMessage(text: "")
        }
    }
    
    func getResponse(data: Data?, error: Error?) {
        DispatchQueue.main.async { [self] in
            apdu.recvData = data?.bytes ?? []
            if (error != nil) {
                status = error.debugDescription
            }
            recvData = apdu.recvData.hexString
            if recvData != "" {
                addMessage(text: "\(recvData)\n")
            }
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
        DispatchQueue.main.async { [self] in
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
        addMessage(text: "< \(sendData)")
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
        pcsc.startSlotMonitor(readerName: selectedReader, getConnectResponse: getConnectResponse, getCardInfo: getCardInfo)
    }
    
    func disconnect() {
        pcsc.stopSlotMonitor()
        connected = false
        cardInfo = CardInfo()
    }
    
    private func specCompare(_ expStr: String, _ cmpStr: String) -> Bool {
        if expStr.subString(0, 1) == "*" {
            return true
        }
        if expStr.count > cmpStr.count {
            return false
        }
        for i in stride(from: 0, to: expStr.count, by: 2) {
            if expStr.subString(i, 1) == "*" {
                return true
            } else if expStr.subString(i, 2) != "XX" {
                if expStr.subString(i, 2) != cmpStr.subString(i, 2) {
                    return false
                }
            }
        }
        return true
    }
    
    private func getScriptResponse(data: Data?, error: Error?) {
        DispatchQueue.main.async { [self] in
            apdu.recvData = data?.bytes ?? []
            if (error != nil) {
                status = error.debugDescription
            }
            let recvStr = apdu.recvData.hexString
            let exRecvStr = lines[line].trimSpaces.uppercased()
            if specCompare(exRecvStr, recvStr) {
                addMessage(text: "> \(recvStr)")
            } else {
                addMessage(text: "> \(recvStr) (Error: expected \(exRecvStr)")
            }
            line += 1
            if line < lines.count - 1 {
                DispatchQueue.main.async { [self] in
                    runScript()
                }
            } else {
                processing = false
            }
        }
    }
    
    func runScript() {
        if connected {
            if !processing {
                processing = true
                lines = script.parseFile(atPath: scriptFile)
                line = 0
            }
            if lines.count > 0 && line < lines.count - 1 {
                let sendData = lines[line].trimSpaces.uppercased()
                apdu.sendData = sendData.hexBytes
                recvData = ""
                status = ""
                addMessage(text: "< \(sendData)")
                line += 1
                pcsc.transferApdu(data: Data(apdu.sendData), getResponse: getScriptResponse)
            }
        }
    }
    
    func documentDirectory() -> String {
        let documentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        return documentDirectory[0]
    }
    
    private func append(toPath path: String, withPathComponent pathComponent: String) -> String? {
        if var pathURL = URL(string: path) {
            pathURL = pathURL.appendingPathComponent(pathComponent)
            return pathURL.absoluteString
        }
        return nil
    }
    
    func saveLog() -> (result: Bool, error: String?) {
        guard let filePath = append(toPath: documentDirectory(), withPathComponent: "apdulog.txt") else {
            return (false, "Path not found")
        }
        do {
            try message.write(toFile: filePath, atomically: true, encoding: .utf8)
        } catch {
            print("Error", error)
            return (false, error.localizedDescription)
        }
        return (true, nil)
    }
    
    func showToast(_ message: String) {
        DispatchQueue.main.async { [self] in
            toastMessage = message
            showToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                showToast = false
            }
        }
    }
}
