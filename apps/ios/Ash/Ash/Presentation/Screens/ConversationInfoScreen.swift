//
//  ConversationInfoScreen.swift
//  Ash
//
//  Conversation details screen
//  Apple HIG compliant design
//

import SwiftUI

struct ConversationInfoScreen: View {
    @Environment(\.dismiss) private var dismiss

    let conversation: Conversation
    var onBurn: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            List {
                // Identity
                Section {
                    LabeledContent("Checksum") {
                        Text(conversation.mnemonicChecksum.prefix(3).joined(separator: " "))
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Role") {
                        Text(conversation.role == .initiator ? "Creator" : "Joiner")
                            .foregroundStyle(.secondary)
                    }
                }

                // Usage
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        DualUsageBar(
                            myUsage: conversation.myUsagePercentage,
                            peerUsage: conversation.peerUsagePercentage,
                            height: 8
                        )

                        HStack {
                            Label("\(Int(conversation.myUsagePercentage * 100))% you", systemImage: "arrow.up.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Label("\(Int(conversation.peerUsagePercentage * 100))% them", systemImage: "arrow.down.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    LabeledContent("Remaining") {
                        Text(conversation.formattedRemaining)
                            .foregroundStyle(conversation.isExhausted ? .red : .secondary)
                    }

                    if conversation.isExhausted {
                        Label("Pad exhausted - no more messages", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Encryption Pad")
                }

                // Settings
                Section {
                    if conversation.disappearingMessages.isEnabled {
                        LabeledContent("Disappearing") {
                            Text(conversation.disappearingMessages.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("Created") {
                        Text(conversation.createdAt, style: .date)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Settings")
                }

                // Danger Zone
                if let onBurn = onBurn {
                    Section {
                        Button(role: .destructive) {
                            onBurn()
                        } label: {
                            Label("Burn Conversation", systemImage: "flame.fill")
                        }
                    } footer: {
                        Text("Permanently destroys this conversation on both devices.")
                    }
                }
            }
            .navigationTitle(conversation.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ConversationInfoScreen(
        conversation: Conversation(
            id: "abc123def456",
            createdAt: Date().addingTimeInterval(-86400 * 7),
            lastActivity: Date(),
            remainingBytes: 200_000,
            totalBytes: 256_000,
            unreadCount: 0,
            mnemonicChecksum: ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot"],
            customName: "Alice",
            role: .initiator,
            sendOffset: 30_000,
            peerConsumed: 26_000,
            relayURL: "https://relay.example.com",
            disappearingMessages: .fiveMinutes,
            authToken: "preview-auth-token",
            burnToken: "preview-burn-token"
        ),
        onBurn: {}
    )
}
