//
//  StateView.swift
//  ApduTool
//
//  Created by Ken Cheung on 1/30/23.
//

import SwiftUI

struct StateView: View {
    @EnvironmentObject var pcsc: PcscViewModel
    var body: some View {
        Text("Card State: \(pcsc.cardState.rawValue)")
            .frame(maxWidth: .infinity, alignment: .center)
        Text(pcsc.status)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct StateView_Previews: PreviewProvider {
    static var previews: some View {
        StateView()
            .environmentObject(PcscViewModel())
    }
}
