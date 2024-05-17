//
//  SelectFileView.swift
//  ApduTool
//
//  Created by Ken Cheung on 4/9/24.
//

import SwiftUI

struct SelectFileView: View {
    @Environment(\.colorScheme) var cs
    @EnvironmentObject var pcsc: PcscViewModel
    @State var fileNames: [String] = []
    @State var selectedFile: String = ""
    var body: some View {
        GeometryReader { screen in
            VStack(alignment: .center) {
                HStack {
                    Button() {
                        pcsc.showSelectFile.toggle()
                    } label: {
                        Text("Back")
                    }
                    .buttonStyle(.bordered)
                    .padding()
                    Spacer()
                    Button() {
                        #if os(macOS)
                        runScript(selectedFile)
                        #endif
                    } label: {
                        Text("Open")
                    }
                    .buttonStyle(.bordered)
                    .padding()
                }
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(fileNames, id: \.self) { fileName in
                            Text(fileName)
                                .font(.title2)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(selectedFile == fileName ? Color.blue : Color.backgroundColor.opacity(0.2))
                                .cornerRadius(10)
                                .onTapGesture {
                                    selectedFile = fileName
                                }
                        }
                    }
                }
                .onAppear {
                    fileNames = pcsc.getFileNames()
                }
            }
            .background {
                Color.backgroundColor
            }
            .opacity(1.0)
            .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 2)
            .padding()
        }
    }
    #if os(macOS)
    func runScript(_ scriptFile: String) {
        if scriptFile != "" {
            pcsc.scriptFile = pcsc.append(toPath: pcsc.documentDirectory(), withPathComponent: scriptFile) ?? ""
            pcsc.showSelectFile.toggle()
            print(pcsc.scriptFile)
            if pcsc.scriptFile != "" {
                pcsc.runScript()
            }
        }
    }
    #endif
}

#Preview {
    SelectFileView()
        .environmentObject(PcscViewModel())
}
