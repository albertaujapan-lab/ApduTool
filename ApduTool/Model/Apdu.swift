//
//  Apdu.swift
//  ApduTool
//
//  Created by Ken Cheung on 1/26/23.
//

import Foundation

public struct Apdu {
    public var sendData: [UInt8] = [UInt8]()
    public var recvData: [UInt8] = [UInt8]()
    
    public init(sendData: [UInt8] = [UInt8](), recvData: [UInt8] = [UInt8]()) {
        self.sendData = sendData
        self.recvData = recvData
    }
}

public struct ApduCommand: Equatable {
    public var cla: UInt8
    public var ins: UInt8
    public var p1: UInt8
    public var p2: UInt8
    public var data: Data?
    public var le: Int?
    public var isExtended: Bool
    
    public init(cla: UInt8, ins: UInt8, p1: UInt8, p2: UInt8, data: Data? = nil, le: Int? = nil, isExtended: Bool = false) {
        self.cla = cla
        self.ins = ins
        self.p1 = p1
        self.p2 = p2
        self.data = data
        self.le = le
        self.isExtended = isExtended
    }
    
    /// Formats the command into raw APDU bytes adhering to ISO/IEC 7816-4
    public var rawBytes: [UInt8] {
        var bytes: [UInt8] = [cla, ins, p1, p2]
        if isExtended {
            if let data = data, !data.isEmpty {
                bytes.append(0x00)
                let lc = data.count
                bytes.append(UInt8((lc >> 8) & 0xFF))
                bytes.append(UInt8(lc & 0xFF))
                bytes.append(contentsOf: [UInt8](data))
                if let le = le {
                    let leVal = (le == 65536) ? 0 : le
                    bytes.append(UInt8((leVal >> 8) & 0xFF))
                    bytes.append(UInt8(leVal & 0xFF))
                }
            } else if let le = le {
                bytes.append(0x00)
                let leVal = (le == 65536) ? 0 : le
                bytes.append(UInt8((leVal >> 8) & 0xFF))
                bytes.append(UInt8(leVal & 0xFF))
            }
        } else {
            if let data = data, !data.isEmpty {
                bytes.append(UInt8(data.count & 0xFF))
                bytes.append(contentsOf: [UInt8](data))
            }
            if let le = le {
                let leByte = (le == 256) ? 0 : UInt8(le & 0xFF)
                bytes.append(leByte)
            }
        }
        return bytes
    }
}
