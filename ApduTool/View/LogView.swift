//
//  LogView.swift
//  ApduTool
//
//  Created by Ken Cheung on 4/8/24.
//

import SwiftUI

struct LogView: View {
    @Namespace var bottomID
    @EnvironmentObject var pcsc: PcscViewModel
    var body: some View {
        VStack {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(pcsc.message)
                            .font(.system(size: 12))
                            .monospaced()
                            .padding(10)
                            .frame(width: geometry.size.width, alignment: .leading)
                        Spacer()
                            .id(bottomID)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                    .onChange(of: pcsc.message) { _ in
                        withAnimation {
                            proxy.scrollTo(bottomID)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    LogView()
        .environmentObject(PcscViewModel())
}
