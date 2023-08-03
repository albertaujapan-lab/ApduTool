//
//  ReadersView.swift
//  ApduTool
//
//  Created by Ken Cheung on 1/27/23.
//

import SwiftUI

struct ReadersView: View {
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
        if isLanscape() {
            HStack {
                Picker(selection: $pcsc.selectedReader, label: Text("Select a reader")) {
                    ForEach(self.pcsc.slotNames, id: \.self) {
                        Text($0)
                    }
                }
                .pickerStyle(.inline)
                .frame(width: screenWidth * 0.6)
                .disabled(pcsc.connected)
                .onReceive(pcsc.slotNames.publisher, perform: { value in
                    if !pcsc.slotNames.contains(pcsc.selectedReader) {
                        pcsc.selectedReader = value
                    }
                })
                Text(pcsc.connected ? "Connected": "Not connected")
                    .frame(width: screenWidth * 0.15)
                Button() {
                    if pcsc.connected {
                        pcsc.disconnect()
                    } else {
                        pcsc.connect()
                    }
                } label: {
                    if pcsc.connected {
                        Text("Disconnect")
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.bordered)
                .frame(width: screenWidth * 0.15)
                Spacer()
            }
        } else {
            VStack {
                Picker(selection: $pcsc.selectedReader, label: Text("Select a reader")) {
                    ForEach(self.pcsc.slotNames, id: \.self) {
                        Text($0)
                    }
                }
                .pickerStyle(.inline)
                .frame(height: 30)
                .disabled(pcsc.connected)
                .onReceive(pcsc.slotNames.publisher, perform: { value in
                    if !pcsc.slotNames.contains(pcsc.selectedReader) {
                        pcsc.selectedReader = value
                    }
                })
                Text(pcsc.connected ? "Connected": "Not connected")
                Button() {
                    if pcsc.connected {
                        pcsc.disconnect()
                    } else {
                        pcsc.connect()
                    }
                } label: {
                    if pcsc.connected {
                        Text("Disconnect")
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct ReadersView_Previews: PreviewProvider {
    static var previews: some View {
        GeometryReader { screen in
            let screenWidth = screen.size.width
            ReadersView(screenWidth: screenWidth)
                .environmentObject(PcscViewModel())
        }
    }
}
