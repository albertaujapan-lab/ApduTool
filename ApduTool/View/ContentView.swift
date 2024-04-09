//
//  ContentView.swift
//  ApduTool
//
//  Created by Ken Cheung on 1/26/23.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var pcsc: PcscViewModel
    var body: some View {
        GeometryReader { screen in
            let screenWidth = screen.size.width
            ZStack {
                VStack {
                    ReadersView(screenWidth: screenWidth)
                    TransferApduView(screenWidth: screenWidth)
                    StateView().padding(.top)
                    ScriptButtonView()
                    LogView()
                    Spacer()
                }
                if pcsc.showSelectFile {
                    SelectFileView()
                        .environmentObject(pcsc)
                }
                if pcsc.showToast {
                    ToastView(message: $pcsc.toastMessage)
                }
            }
        }.padding(.horizontal)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(PcscViewModel())
    }
}
