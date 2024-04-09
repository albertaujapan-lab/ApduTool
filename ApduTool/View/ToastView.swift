//
//  ToastView.swift
//  ApduTool
//
//  Created by Ken Cheung on 4/8/24.
//

import SwiftUI

struct ToastView: View {
    @Binding var message: String

    var body: some View {
        Text(message)
            .padding()
            .background(Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.horizontal, 20)
            .transition(.opacity)
            .animation(.default, value: 10)
    }
}

#Preview {
    @State var message = "hello"
    return ToastView(message: $message)
}
