//
//  ScriptButtonView.swift
//  ApduTool
//
//  Created by Ken Cheung on 4/8/24.
//

import SwiftUI

struct ScriptButtonView: View {
    @EnvironmentObject var pcsc: PcscViewModel
    @State var openFile = false
    var body: some View {
        HStack(alignment: .center) {
            Button() {
                if pcsc.connected {
                    self.openFile.toggle()
                }
            } label: {
                Text("Run Script")
            }
            .disabled(!pcsc.connected || pcsc.processing)
            .fileImporter(isPresented: $openFile, allowedContentTypes: [.text], onCompletion: { result in
                do {
                    let fileURL = try result.get()
                    if fileURL.startAccessingSecurityScopedResource() {
                        pcsc.scriptFile = fileURL.relativePath
                        if pcsc.scriptFile != "" {
                            pcsc.runScript()
                        }
                        fileURL.stopAccessingSecurityScopedResource()
                    } else {
                        pcsc.showToast("Cannot open file")
                    }
                }
                catch {
                    let message = "error reading file \(error.localizedDescription)"
                    print(message)
                    pcsc.showToast(message)
                }
            })
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
