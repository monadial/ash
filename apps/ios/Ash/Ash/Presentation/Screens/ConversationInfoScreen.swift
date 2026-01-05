//
//  ConversationInfoScreen.swift
//  Ash
//
//  Conversation details - Modern redesign with color picker
//

import SwiftUI

struct ConversationInfoScreen: View {
    @Environment(\.dismiss) private var dismiss

    let conversation: Conversation
    var onColorChange: ((ConversationColor) -> Void)? = nil
    var onBurn: (() -> Void)? = nil

    @State private var selectedColor: ConversationColor

    init(conversation: Conversation, onColorChange: ((ConversationColor) -> Void)? = nil, onBurn: (() -> Void)? = nil) {
        self.conversation = conversation
        self.onColorChange = onColorChange
        self.onBurn = onBurn
        self._selectedColor = State(initialValue: conversation.accentColor)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header with avatar
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(selectedColor.color.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Text(conversation.avatarInitials)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(selectedColor.color)
                        }

                        Text(conversation.displayName)
                            .font(.title2.bold())

                        // Mnemonic checksum
                        Text(conversation.mnemonicChecksum.prefix(3).joined(separator: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 24)

                    // Color Picker Section
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "paintpalette")
                                .font(.title3)
                                .foregroundStyle(selectedColor.color)
                                .frame(width: 32)
                            Text("Theme Color")
                                .font(.subheadline.bold())
                            Spacer()
                        }
                        .padding(16)

                        Divider().padding(.leading, 56)

                        // Color grid
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                            ForEach(ConversationColor.allCases) { color in
                                ColorPickerButton(
                                    color: color,
                                    isSelected: selectedColor == color,
                                    onSelect: {
                                        withAnimation(.spring(duration: 0.2)) {
                                            selectedColor = color
                                        }
                                        onColorChange?(color)
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)

                    // Identity Section
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "person.badge.key")
                                .font(.title3)
                                .foregroundStyle(selectedColor.color)
                                .frame(width: 32)
                            Text("Identity")
                                .font(.subheadline.bold())
                            Spacer()
                        }
                        .padding(16)

                        Divider().padding(.leading, 56)

                        InfoRow(label: "Role", value: conversation.role == .initiator ? "Creator" : "Joiner")
                        Divider().padding(.leading, 56)
                        InfoRow(label: "Created", value: conversation.createdAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    // Encryption Pad Section
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "lock.shield")
                                .font(.title3)
                                .foregroundStyle(selectedColor.color)
                                .frame(width: 32)
                            Text("Encryption Pad")
                                .font(.subheadline.bold())
                            Spacer()
                        }
                        .padding(16)

                        Divider().padding(.leading, 56)

                        // Usage visualization
                        VStack(spacing: 12) {
                            DualUsageBar(
                                myUsage: conversation.myUsagePercentage,
                                peerUsage: conversation.peerUsagePercentage,
                                accentColor: selectedColor.color,
                                height: 10
                            )

                            HStack {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(selectedColor.color)
                                        .frame(width: 8, height: 8)
                                    Text("\(Int(conversation.myUsagePercentage * 100))% You")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.secondary.opacity(0.5))
                                        .frame(width: 8, height: 8)
                                    Text("\(Int(conversation.peerUsagePercentage * 100))% Them")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider().padding(.leading, 56)

                        InfoRow(
                            label: "Remaining",
                            value: conversation.formattedRemaining,
                            valueColor: conversation.isExhausted ? .red : nil
                        )

                        if conversation.isExhausted {
                            Divider().padding(.leading, 56)
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text("Pad exhausted - no more messages")
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    // Settings Section
                    if conversation.disappearingMessages.isEnabled {
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "timer")
                                    .font(.title3)
                                    .foregroundStyle(selectedColor.color)
                                    .frame(width: 32)
                                Text("Settings")
                                    .font(.subheadline.bold())
                                Spacer()
                            }
                            .padding(16)

                            Divider().padding(.leading, 56)

                            InfoRow(label: "Disappearing Messages", value: conversation.disappearingMessages.displayName)
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }

                    // Danger Zone
                    if let onBurn = onBurn {
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "flame")
                                    .font(.title3)
                                    .foregroundStyle(.red)
                                    .frame(width: 32)
                                Text("Danger Zone")
                                    .font(.subheadline.bold())
                                Spacer()
                            }
                            .padding(16)

                            Divider().padding(.leading, 56)

                            Button(role: .destructive) {
                                onBurn()
                            } label: {
                                HStack {
                                    Label("Burn Conversation", systemImage: "flame.fill")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }

                            Text("Permanently destroys this conversation on both devices.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }

                    Spacer().frame(height: 40)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(selectedColor.color)
                }
            }
        }
    }
}

// MARK: - Color Picker Button

private struct ColorPickerButton: View {
    let color: ConversationColor
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                Circle()
                    .fill(color.color)
                    .frame(width: 44, height: 44)

                if isSelected {
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                        .frame(width: 44, height: 44)

                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Info Row

private struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueColor ?? .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
            accentColor: .purple,
            authToken: "preview-auth-token",
            burnToken: "preview-burn-token"
        ),
        onColorChange: { _ in },
        onBurn: {}
    )
}
