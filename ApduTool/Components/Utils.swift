//
//  Utils.swift
//  ApduTool
//
//  Created by Ken Cheung on 1/26/23.
//

import SwiftUI

extension Data {
    var bytes: [UInt8] {
        return [UInt8](self)
    }
}

extension StringProtocol {
    var hexBytes: [UInt8] {
        var startIndex = self.startIndex
        return (0..<count/2).compactMap { _ in
            let endIndex = index(after: startIndex)
            defer { startIndex = index(after: endIndex) }
            return UInt8(self[startIndex...endIndex], radix: 16)
        }
    }
    var trimSpaces: String {
        return self.replacingOccurrences(of: " ", with: "")
    }
}

extension [UInt8] {
    var hexString: String {
        var hexString: String = ""
        for byte in self
        {
            hexString.append(String(format:"%02X", byte))
        }
        return hexString
    }
}
