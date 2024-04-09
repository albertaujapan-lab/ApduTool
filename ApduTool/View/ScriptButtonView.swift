//
//  ScriptButtonView.swift
//  ApduTool
//
//  Created by Ken Cheung on 4/8/24.
//

import SwiftUI

struct ScriptButtonView: View {
    @EnvironmentObject var pcsc: PcscViewModel
    var body: some View {
        HStack(alignment: .center) {
            Button() {
                if pcsc.connected {
                    pcsc.showSelectFile.toggle()
                }
            } label: {
                Text("Run Script")
            }
            .disabled(!pcsc.connected || pcsc.processing)
            .buttonStyle(.bordered)
            .padding(.horizontal)
            Button() {
                var message = "Nothing to save"
                if pcsc.message != "" {
                    let (result, error) = pcsc.saveLog()
                    if (result) {
                        message = "File saved successfully."
                    } else {
                        message = "Error saving file: \(error!)"
                    }
                }
                print(message)
                pcsc.showToast(message)
            } label: {
                Text("Save Log")
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
        }
    }
}

#Preview {
    ScriptButtonView()
        .environmentObject(PcscViewModel())
}
