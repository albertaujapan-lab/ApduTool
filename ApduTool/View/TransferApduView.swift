//
//  TransferApduView.swift
//  ApduTool
//
//  Created by Ken Cheung on 1/27/23.
//

import SwiftUI

struct TransferApduView: View {
#if !os(macOS)
    @Environment(\.verticalSizeClass) var verticalSizeClass: UserInterfaceSizeClass?
    @Environment(\.horizontalSizeClass) var horizontalSizeClass: UserInterfaceSizeClass?
#endif
    @EnvironmentObject var pcsc: PcscViewModel
    var screenWidth: CGFloat
#if os(macOS)
    func isLanscape() -> Bool { return true }
#else
    func isLanscape() -> Bool { return horizontalSizeClass == .regular }
#endif
    var body: some View {
        VStack {
            if isLanscape() {
                HStack {
                    Text("Send APDU:").frame(width: screenWidth * 0.15, alignment: .trailing)
                    TextField("", text: $pcsc.sendData)
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .frame(width: screenWidth * 0.6, height: 28, alignment: .leading)
                        .border(.blue)
                        .onChange(of: pcsc.sendData, perform: { newValue in
                            pcsc.sendData = newValue.uppercased().filter("0123456789ABCDEF".contains)
                        })
                    Button() {
                        if pcsc.sendData.starts(with: "E0") {
                            pcsc.transferEscapeCommand()
                        } else {
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
                        .frame(width: screenWidth * 0.6, height: 28, alignment: .leading)
                        .border(.blue)
                    Spacer()
                }
            } else {
                VStack {
                    Text("Send APDU:")
                        .frame(width: screenWidth * 9 / 10, height: 32, alignment: .leading)
                    TextField("", text: $pcsc.sendData)
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .font(.system(size: 20))
                        .monospaced()
                        .padding(4)
                        .frame(width: screenWidth * 9 / 10, height: 32, alignment: .leading)
                        .border(.blue)
                        .onChange(of: pcsc.sendData, perform: { newValue in
                            pcsc.sendData = newValue.uppercased().filter("0123456789ABCDEF".contains)
                        })
                    Button() {
                        if pcsc.sendData.starts(with: "E0") {
                            pcsc.transferEscapeCommand()
                        } else {
                            pcsc.transferApdu()
                        }
                    } label: {
                        Text("Transmit")
                    }
                    .buttonStyle(.bordered)
                    .frame(width: screenWidth)
                    Text("Recv APDU:")
                        .frame(width: screenWidth * 9 / 10, alignment: .leading)
                    Text(pcsc.recvData)
                        .font(.system(size: 20))
                        .padding(4)
                        .frame(width: screenWidth * 9 / 10, height: 32, alignment: .leading)
                        .border(.blue)
                }
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
