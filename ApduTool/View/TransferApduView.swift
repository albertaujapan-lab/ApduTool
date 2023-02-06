//
//  TransferApduView.swift
//  ApduTool
//
//  Created by Ken Cheung on 1/27/23.
//

import SwiftUI

struct TransferApduView: View {
    @EnvironmentObject var pcsc: PcscViewModel
    var screenWidth: CGFloat
    var body: some View {
        VStack {
            HStack {
                Text("Send APDU:").frame(width: screenWidth * 0.15, alignment: .trailing)
                TextField("", text: $pcsc.sendData)
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .frame(width: screenWidth * 0.6, alignment: .leading)
                    .border(.blue)
                    .onChange(of: pcsc.sendData, perform: { newValue in
                        pcsc.sendData = newValue.uppercased().filter("0123456789ABCDEF".contains)
                    })
                Button() {
                    if (pcsc.sendData.starts(with: "E0")) {
                        pcsc.transferEscapeCommand()
                    } else if (pcsc.connected) {
                        pcsc.transferApdu()
                    }
                } label: {
                    Text("Transmit")
                }
                .buttonStyle(.bordered)
                .frame(width: screenWidth * 0.15)
                Spacer()
            }
            HStack {
                Text("Recv APDU:").frame(width: screenWidth * 0.15, alignment: .trailing)
                Text(pcsc.recvData)
                    .frame(width: screenWidth * 0.6, alignment: .leading)
                    .border(.blue)
                Spacer()
            }
        }
    }
}

struct TransferApduView_Previews: PreviewProvider {
    static var previews: some View {
        GeometryReader { screen in
            let screenWidth = screen.size.width
            TransferApduView(screenWidth: screenWidth)
                .environmentObject(PcscViewModel())
        }
    }
}
