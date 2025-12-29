//
//  ContentView.swift
//  Ash
//
//  Created by Tomas Mihalicka on 29/12/2025.
//

import SwiftUI

struct ContentView: View {
    @State private var mnemonicWords: [String] = []

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .imageScale(.large)
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text("Ash Secure Messaging")
                .font(.title)

            if !mnemonicWords.isEmpty {
                Text(mnemonicWords.joined(separator: " "))
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }

            Button("Generate Mnemonic") {
                // Test the FFI bridge
                let testData: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE]
                mnemonicWords = generateMnemonic(padBytes: testData)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
