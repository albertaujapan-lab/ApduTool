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
    @Published var datalog: String = ""
    @Published var autoIsoHandling: Bool = true {
        didSet {
            pcsc.autoIsoHandling = autoIsoHandling
        }
    }
    var currentLoop: Int = 0
    var totalLoops: Int = 1
    var passCount: Int = 0
    var failCount: Int = 0
    var currentLoopFailed: Bool = false
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
        pcsc.autoIsoHandling = autoIsoHandling
        pcsc.onLogMessage = { [weak self] msg in
            self?.addMessage(text: msg)
        }
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
    
    private var displayLines: [String] = []
    public let maxDisplayLines: Int = 1000

    private static let logDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()

    func addMessage(text: String) {
        if Thread.isMainThread {
            appendMessage(text: text)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.appendMessage(text: text)
            }
        }
    }

    func appendMessage(text: String) {
        if !text.isEmpty {
            let timeStamp = PcscViewModel.logDateFormatter.string(from: Date())
            let cleanText = text.hasSuffix("\n") ? String(text.dropLast()) : text
            let logEntry = "\(timeStamp): \(cleanText)\n"
            
            // 1. datalog maintains the complete history of all loops for saving
            datalog.append(logEntry)
            
            // 2. message only maintains the latest maxDisplayLines (1000 lines) for UI display performance
            displayLines.append(logEntry)
            if displayLines.count > maxDisplayLines {
                displayLines.removeFirst(displayLines.count - maxDisplayLines)
            }
            message = displayLines.joined()
        } else {
            displayLines.removeAll()
            message = ""
            datalog = ""
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
        pcsc.transferApdu(data: Data(apdu.sendData), autoIsoHandling: autoIsoHandling, getResponse: getResponse)
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
    
    func resetCard(completion: ((Bool) -> Void)? = nil) {
        pcsc.resetCard { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let atr):
                    self.cardInfo.atr = atr.hexString
                    self.cardInfo.currentProtocol = self.getProtocolString(self.pcsc.getCurrentProtocol())
                    self.addMessage(text: "ATR:")
                    if !atr.isEmpty {
                        self.addMessage(text: atr.hexString)
                    } else {
                        self.addMessage(text: "(empty)")
                    }
                    completion?(true)
                case .failure(let error):
                    self.currentLoopFailed = true
                    self.status = error.localizedDescription
                    self.addMessage(text: "Error: " + error.localizedDescription)
                    completion?(false)
                }
            }
        }
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
    
    private func finishStepAndContinue() {
        if line < lines.count {
            DispatchQueue.main.async { [self] in
                runScript()
            }
        } else {
            if currentLoopFailed {
                failCount += 1
                addMessage(text: "Loop# \(currentLoop + 1) fail")
            } else {
                passCount += 1
                addMessage(text: "Loop# \(currentLoop + 1) pass")
            }
            currentLoop += 1
            if currentLoop < totalLoops {
                line = 0
                currentLoopFailed = false
                DispatchQueue.main.async { [self] in
                    runScript()
                }
            } else {
                addMessage(text: "Pass: \(passCount) and Fail: \(failCount)")
                processing = false
            }
        }
    }
    
    private func getScriptResponse(data: Data?, error: Error?) {
        DispatchQueue.main.async { [self] in
            guard connected else {
                failCount += 1
                addMessage(text: "Loop# \(currentLoop + 1) fail")
                addMessage(text: "Pass: \(passCount) and Fail: \(failCount)")
                processing = false
                return
            }
            apdu.recvData = data?.bytes ?? []
            if (error != nil) {
                status = error.debugDescription
            }
            let recvStr = apdu.recvData.hexString
            let exRecvStr = lines[line].trimSpaces.uppercased()
            let matched = !recvStr.isEmpty && specCompare(exRecvStr, recvStr)
            if matched {
                status = ""
                addMessage(text: "> \(recvStr)")
            } else {
                currentLoopFailed = true
                if error != nil {
                    status = error!.localizedDescription
                    addMessage(text: "> \(recvStr) (Error: \(error!.localizedDescription))")
                } else {
                    status = "Expected \(exRecvStr)"
                    addMessage(text: "> \(recvStr) (Error: expected \(exRecvStr))")
                }
            }
            line += 1
            finishStepAndContinue()
        }
    }
    
    func runScript() {
        if connected {
            if !processing {
                processing = true
                validateLoopOnEnd()
                totalLoops = Int(loop) ?? 1
                currentLoop = 0
                passCount = 0
                failCount = 0
                currentLoopFailed = false
                addMessage(text: "")
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
            guard lines.count > 0 && line < lines.count else {
                processing = false
                return
            }
            if line == 0 {
                currentLoopFailed = false
                addMessage(text: "Loop# \(currentLoop + 1)/\(totalLoops) starts")
            }
            
            let currentLine = lines[line].trimSpaces
            if currentLine.uppercased().contains("[RST]") {
                addMessage(text: "< [RST]")
                line += 1
                var expectedAtr: String? = nil
                if line < lines.count {
                    let nextCandidate = lines[line].trimSpaces.uppercased()
                    if nextCandidate.starts(with: "3B") || nextCandidate.starts(with: "3F") || nextCandidate == "*" {
                        expectedAtr = nextCandidate
                        line += 1
                    }
                }
                resetCard { [weak self] success in
                    guard let self = self else { return }
                    if let expected = expectedAtr {
                        let actualAtr = self.cardInfo.atr.trimSpaces.uppercased()
                        if !self.specCompare(expected, actualAtr) {
                            self.currentLoopFailed = true
                            self.addMessage(text: "> Error: expected ATR \(expected)")
                        }
                    }
                    self.finishStepAndContinue()
                }
                return
            }
            
            if line < lines.count - 1 {
                let sendData = currentLine.uppercased()
                apdu.sendData = sendData.hexBytes
                recvData = ""
                status = ""
                addMessage(text: "< \(sendData)")
                line += 1
                pcsc.transferApdu(data: Data(apdu.sendData), autoIsoHandling: autoIsoHandling, getResponse: getScriptResponse)
            } else {
                let sendData = currentLine.uppercased()
                apdu.sendData = sendData.hexBytes
                recvData = ""
                status = ""
                addMessage(text: "< \(sendData)")
                line += 1
                pcsc.transferApdu(data: Data(apdu.sendData), autoIsoHandling: autoIsoHandling) { [weak self] data, error in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        if let error = error {
                            self.currentLoopFailed = true
                            self.addMessage(text: "> Error: \(error.localizedDescription)")
                        } else if let data = data {
                            self.addMessage(text: "> \(data.bytes.hexString)")
                        }
                        self.finishStepAndContinue()
                    }
                }
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
            let logToSave = !datalog.isEmpty ? datalog : message
            try logToSave.write(toFile: filePath, atomically: true, encoding: .utf8)
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
