//
//  ReadersView.swift
//  ApduTool
//
//  Created by Ken Cheung on 1/27/23.
//

import SwiftUI

struct ReadersView: View {
    @State var selectedReader: String = ""
    @EnvironmentObject var pcsc: PcscViewModel
    var screenWidth: CGFloat
    var body: some View {
        HStack {
            Picker(selection: $selectedReader, label: Text("Select a reader")) {
                ForEach(self.pcsc.slotNames, id: \.self) {
                    Text($0)
                }
            }
            .pickerStyle(.inline)
            .frame(width: screenWidth * 0.6)
            .disabled(pcsc.connected)
            .onReceive(pcsc.slotNames.publisher, perform: { value in
                if (selectedReader == "" || !pcsc.slotNames.contains(selectedReader)) {
                    selectedReader = value
                }
            })
            Text(pcsc.connected ? "Connected": "Not connected")
                .frame(width: screenWidth * 0.15)
            Button() {
                if (pcsc.connected) {
                    pcsc.disconnect()
                } else {
                    pcsc.connect(readerName: selectedReader)
                }
            } label: {
                if (pcsc.connected) {
                    Text("Disconnect")
                } else {
                    Text("Connect")
                }
            }
            .buttonStyle(.bordered)
            .frame(width: screenWidth * 0.15)
            Spacer()
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
