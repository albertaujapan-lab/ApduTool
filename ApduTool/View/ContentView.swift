//
//  ContentView.swift
//  ApduTool
//
//  Created by Ken Cheung on 1/26/23.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var pcsc: Pcsc
    var body: some View {
        GeometryReader { screen in
            let screenWidth = screen.size.width
            VStack {
                ReadersView(screenWidth: screenWidth)
                TransferApduView(screenWidth: screenWidth)
                StateView().padding(.top)
                Spacer()
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
