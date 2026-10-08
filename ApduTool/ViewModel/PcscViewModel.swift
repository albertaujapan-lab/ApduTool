//
//  PcscViewModel.swift
//  ApduTool
//
//  Created by Ken Cheung on 1/30/23.
//

import Foundation
#if os(iOS)
import UIKit
import MobileCoreServices
#endif
import CryptoTokenKit

class PcscViewModel: NSObject, ObservableObject {
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
    @Published var showSelectFile: Bool = false
    @Published var loop: String = "1"
    var currentLoop: Int = 0
    var totalLoops: Int = 1
#if os(macOS)
    var scriptFile: String = ""
#else
    var scriptURL: URL? = nil
    var readWrite: Bool = false
#endif
    var lines: [String] = []
    var line: Int = 0
    var apdu: Apdu = Apdu()
    var pcsc: Pcsc = Pcsc()
    var script: Script = Script()
    
    override init() {
        super.init()
        slotNames = pcsc.getSlotNames()
        pcsc.setUpdateCardSlots(self.updateCardSlots)
    }
    
    func validateLoopInput(_ newValue: String) {
        let filtered = newValue.filter { "-0123456789".contains($0) }
        if let val = Int(filtered) {
            if val <= 0 {
                loop = "1"
            } else if filtered != newValue {
                loop = filtered
            }
        } else if filtered.isEmpty || filtered == "-" {
            if filtered != newValue {
                loop = filtered
            }
        } else {
            loop = "1"
        }
    }
    
    func validateLoopOnEnd() {
        if let val = Int(loop), val > 0 {
            loop = String(val)
        } else {
            loop = "1"
        }
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
                addMessage(text: "> \(recvData)\n")
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
                status = error!.localizedDescription
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
        processing = false
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
            guard connected else {
                processing = false
                return
            }
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
                currentLoop += 1
                if currentLoop < totalLoops {
                    line = 0
                    DispatchQueue.main.async { [self] in
                        runScript()
                    }
                } else {
                    processing = false
                }
            }
        }
    }
    
    func runScript() {
        if connected {
            if !processing {
                processing = true
                validateLoopOnEnd()
                totalLoops = Int(loop) ?? 1
                currentLoop = 0
#if os(macOS)
                lines = script.parseFile(atPath: scriptFile)
#else
                // Request temporary access to the security-scoped resource
                guard let accessGranted = scriptURL?.startAccessingSecurityScopedResource() else {
                    showToast("Invalid file")
                    processing = false
                    return
                }
                if accessGranted {
                    lines = script.parseFile(atPath: scriptURL!.relativePath)
                    scriptURL?.stopAccessingSecurityScopedResource()
                } else {
                    showToast("Access is denied")
                    processing = false
                    return
                }
#endif
                line = 0
            }
            if lines.count > 1 && line < lines.count - 1 {
                let sendData = lines[line].trimSpaces.uppercased()
                apdu.sendData = sendData.hexBytes
                recvData = ""
                status = ""
                addMessage(text: "< \(sendData)")
                line += 1
                pcsc.transferApdu(data: Data(apdu.sendData), getResponse: getScriptResponse)
            } else if lines.count <= 1 {
                processing = false
            }
        }
    }
    
    func documentDirectory() -> String {
        let documentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        return documentDirectory[0]
    }
    
    func append(toPath path: String, withPathComponent pathComponent: String) -> String? {
        if var pathURL = URL(string: path) {
            pathURL = pathURL.appendingPathComponent(pathComponent)
            return pathURL.relativePath
        }
        return nil
    }
    
    func getFileNames() -> [String] {
        let documentURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentURL, includingPropertiesForKeys: nil)
            let fileNames = fileURLs.map { $0.lastPathComponent }
            return fileNames
        } catch {
            print("Error while enumerating files: \(error.localizedDescription)")
            return []
        }
    }
    
    private func getLogPath() -> String? {
        return append(toPath: documentDirectory(), withPathComponent: "apdulog.txt")
    }
    
    func saveLog() -> (result: Bool, error: String?) {
        guard let filePath = getLogPath() else {
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

#if os(iOS)
extension PcscViewModel : UIDocumentPickerDelegate {
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if readWrite {
            let message = urls.first != nil ? "File saved successfully." : "Error saving file."
            showToast(message)
        } else {
            scriptURL = urls.first
            runScript()
        }
    }
    
    func presentDocumentPicker(_ readWrite: Bool) {
        self.readWrite = readWrite
        var documentPicker: UIDocumentPickerViewController
        if readWrite {
            guard let filePath = getLogPath() else {
                return
            }
            let logFileURL = URL(fileURLWithPath: filePath)
            documentPicker = UIDocumentPickerViewController(forExporting: [logFileURL], asCopy: true)
        } else {
            documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.text])
        }
        documentPicker.allowsMultipleSelection = false
        documentPicker.delegate = self
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first
        window?.rootViewController?.present(documentPicker, animated: true, completion: nil)
    }
}
#endif
