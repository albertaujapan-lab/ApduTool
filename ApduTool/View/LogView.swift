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
    @State private var timer: Timer?
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
                    .onChange(of: pcsc.processing) { processing in
                        if processing {
                            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { _ in
                                withAnimation {
                                    proxy.scrollTo(bottomID)
                                }
                                if !pcsc.processing {
                                    timer?.invalidate()
                                    timer = nil
                                }
                            })
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
