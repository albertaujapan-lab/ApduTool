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
                ScrollView {
                    VStack(spacing: 20) {
                        HStack {
                            Spacer()
                            Button() {
                                runScript(selectedFile)
                            } label: {
                                Text("Open")
                            }
                            .buttonStyle(.bordered)
                            .padding(.horizontal)
                        }
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
                .background {
                    Color.backgroundColor
                }
                .opacity(1.0)
                .onAppear {
                    fileNames = pcsc.getFileNames()
                }
            }
            .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 2)
        }
    }

    func runScript(_ scriptFile: String) {
        if scriptFile != "" {
            pcsc.scriptFile = pcsc.append(toPath: pcsc.documentDirectory(), withPathComponent: scriptFile) ?? ""
            pcsc.showSelectFile.toggle()
            guard let fileURL = URL(string: pcsc.scriptFile) else {
                return
            }
            print(fileURL.relativePath)
            pcsc.scriptFile = fileURL.relativePath
            if pcsc.scriptFile != "" {
                pcsc.runScript()
            }
        }
    }
}

#Preview {
    SelectFileView()
        .environmentObject(PcscViewModel())
}
