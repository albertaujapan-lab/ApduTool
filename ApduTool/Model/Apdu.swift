//
//  Apdu.swift
//  ApduTool
//
//  Created by Ken Cheung on 1/26/23.
//

import Foundation

struct Apdu {
    var sendData: [UInt8] = [UInt8]()
    var recvData: [UInt8] = [UInt8]()
}
