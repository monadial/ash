//
//  ConversationInfoScreen.swift
//  Ash
//
//  Conversation details - Read-only info with all metadata
//  Settings are fixed at ceremony creation and cannot be edited
//

import SwiftUI

struct ConversationInfoScreen: View {
    @Environment(\.dismiss) private var dismiss

    let conversation: Conversation
    var onBurn: (() -> Void)? = nil

    // Server ping state
    @State private var pingLatencyMs: Int?
    @State private var isPinging = false
    @State private var pingError: String?

    private var accentColor: Color { conversation.accentColor.color }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header with avatar and name
                    headerSection

                    // Security Verification Section (all 6 words)
                    securitySection
                        .padding(.top, 12)

                    // Conversation ID Section
                    identifierSection
                        .padding(.top, 12)

                    // Identity Section (role, created date)
                    identitySection
                        .padding(.top, 12)

                    // Relay Server Section (with ping)
                    relaySection
                        .padding(.top, 12)

                    // Message Settings Section (TTL, disappearing)
                    messageSettingsSection
                        .padding(.top, 12)

                    // Encryption Pad Section (detailed consumption)
                    encryptionSection
                        .padding(.top, 12)

                    // Danger Zone
                    if onBurn != nil {
                        dangerSection
                            .padding(.top, 12)
                    }

                    Spacer().frame(height: 40)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Conversation Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(accentColor)
                }
            }
            .task {
                await measurePing()
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)

                Text(conversation.avatarInitials)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            VStack(spacing: 4) {
                Text(conversation.displayName)
                    .font(.title2.bold())

                // Theme color indicator (read-only)
                HStack(spacing: 6) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 10, height: 10)
                    Text(conversation.accentColor.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Security Verification Section (all 6 codes)

    private var securitySection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "checkmark.shield")
                    .font(.title3)
                    .foregroundStyle(accentColor)
                    .frame(width: 32)
                Text("Security Verification")
                    .font(.subheadline.bold())
                Spacer()
            }
            .padding(16)

            Divider().padding(.leading, 56)

            // All 6 mnemonic words in a grid
            VStack(spacing: 8) {
                Text("Both parties must have identical codes:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(Array(conversation.mnemonicChecksum.enumerated()), id: \.offset) { index, word in
                        HStack(spacing: 4) {
                            Text("\(index + 1).")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(width: 16, alignment: .trailing)
                            Text(word)
                                .font(.system(.subheadline, design: .monospaced, weight: .medium))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: - Identifier Section

    private var identifierSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "number")
                    .font(.title3)
                    .foregroundStyle(accentColor)
                    .frame(width: 32)
                Text("Conversation ID")
                    .font(.subheadline.bold())
                Spacer()
            }
            .padding(16)

            Divider().padding(.leading, 56)

            HStack {
                Text(formatConversationId(conversation.id))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    UIPasteboard.general.string = conversation.id
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.subheadline)
                        .foregroundStyle(accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "person.badge.key")
                    .font(.title3)
                    .foregroundStyle(accentColor)
                    .frame(width: 32)
                Text("Identity")
                    .font(.subheadline.bold())
                Spacer()
            }
            .padding(16)

            Divider().padding(.leading, 56)

            InfoRow(label: "Your Role", value: conversation.role == .initiator ? "Initiator (A)" : "Responder (B)")
            Divider().padding(.leading, 56)
            InfoRow(label: "Created", value: conversation.createdAt.formatted(date: .abbreviated, time: .shortened))
            Divider().padding(.leading, 56)
            InfoRow(label: "Last Activity", value: conversation.lastActivity.formatted(.relative(presentation: .named)))
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: - Relay Server Section

    private var relaySection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.title3)
                    .foregroundStyle(accentColor)
                    .frame(width: 32)
                Text("Relay Server")
                    .font(.subheadline.bold())
                Spacer()
            }
            .padding(16)

            Divider().padding(.leading, 56)

            // Relay URL
            HStack {
                Text("URL")
                    .font(.subheadline)
                Spacer()
                Text(formatRelayURL(conversation.relayURL))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().padding(.leading, 56)

            // Server ping
            HStack {
                Text("Latency")
                    .font(.subheadline)
                Spacer()
                if isPinging {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let error = pingError {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                } else if let latency = pingLatencyMs {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(pingColor(latency))
                            .frame(width: 8, height: 8)
                        Text("\(latency) ms")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("—")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await measurePing() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(accentColor)
                }
                .disabled(isPinging)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: - Message Settings Section

    private var messageSettingsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "timer")
                    .font(.title3)
                    .foregroundStyle(accentColor)
                    .frame(width: 32)
                Text("Message Settings")
                    .font(.subheadline.bold())
                Spacer()
            }
            .padding(16)

            Divider().padding(.leading, 56)

            InfoRow(label: "Server Retention", value: MessageTTL.displayName)
            Divider().padding(.leading, 56)
            InfoRow(
                label: "Disappearing Messages",
                value: conversation.disappearingMessages.displayName,
                valueColor: conversation.disappearingMessages.isEnabled ? accentColor : nil
            )

            Divider().padding(.leading, 56)

            // Message persistence (local storage)
            InfoRow(
                label: "Local Storage",
                value: conversation.persistenceConsent ? "Enabled" : "Off",
                valueColor: conversation.persistenceConsent ? accentColor : nil
            )

            // Explanation
            if conversation.persistenceConsent {
                Text("Messages are stored locally between sessions (requires Face ID). They auto-delete when disappearing timer expires.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                Text("Server retention: how long unread messages wait on server. Disappearing: how long messages stay visible after reading. Messages are cleared when you close the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: - Encryption Pad Section

    private var encryptionSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "lock.shield")
                    .font(.title3)
                    .foregroundStyle(accentColor)
                    .frame(width: 32)
                Text("Encryption Pad")
                    .font(.subheadline.bold())
                Spacer()
            }
            .padding(16)

            Divider().padding(.leading, 56)

            // Total size
            InfoRow(label: "Total Size", value: formatBytes(conversation.totalBytes))

            Divider().padding(.leading, 56)

            // Consumed by initiator (A)
            InfoRow(
                label: "Consumed by A (Initiator)",
                value: formatBytes(initiatorConsumed),
                valueColor: conversation.role == .initiator ? accentColor : nil
            )

            Divider().padding(.leading, 56)

            // Consumed by responder (B)
            InfoRow(
                label: "Consumed by B (Responder)",
                value: formatBytes(responderConsumed),
                valueColor: conversation.role == .responder ? accentColor : nil
            )

            Divider().padding(.leading, 56)

            // Remaining
            InfoRow(
                label: "Remaining",
                value: formatBytes(conversation.dynamicRemainingBytes),
                valueColor: conversation.isExhausted ? .red : .green
            )

            Divider().padding(.leading, 56)

            // Usage visualization
            VStack(spacing: 12) {
                DualUsageBar(
                    myUsage: conversation.myUsagePercentage,
                    peerUsage: conversation.peerUsagePercentage,
                    accentColor: accentColor,
                    height: 10
                )

                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(accentColor)
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

            if conversation.isExhausted {
                Divider().padding(.leading, 56)
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Pad exhausted - no more messages possible")
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
    }

    // MARK: - Danger Section

    private var dangerSection: some View {
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
                onBurn?()
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

            Text("Permanently destroys this conversation on both devices. Cannot be undone.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: - Helpers

    /// Bytes consumed by initiator (forward from 0)
    private var initiatorConsumed: UInt64 {
        switch conversation.role {
        case .initiator:
            return conversation.sendOffset
        case .responder:
            return conversation.peerConsumed
        }
    }

    /// Bytes consumed by responder (backward from end)
    private var responderConsumed: UInt64 {
        switch conversation.role {
        case .initiator:
            return conversation.peerConsumed
        case .responder:
            return conversation.sendOffset
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }

    private func formatConversationId(_ id: String) -> String {
        // Show first 8 and last 8 characters with ellipsis
        if id.count > 20 {
            let prefix = String(id.prefix(8))
            let suffix = String(id.suffix(8))
            return "\(prefix)...\(suffix)"
        }
        return id
    }

    private func formatRelayURL(_ url: String) -> String {
        // Remove protocol prefix for display
        url.replacingOccurrences(of: "https://", with: "")
           .replacingOccurrences(of: "http://", with: "")
    }

    private func pingColor(_ latency: Int) -> Color {
        switch latency {
        case 0..<100: return .green
        case 100..<300: return .yellow
        default: return .orange
        }
    }

    private func measurePing() async {
        isPinging = true
        pingError = nil

        guard let url = URL(string: conversation.relayURL)?.appendingPathComponent("health") else {
            pingError = "Invalid URL"
            isPinging = false
            return
        }

        let startTime = Date()

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let elapsed = Date().timeIntervalSince(startTime)
                pingLatencyMs = Int(elapsed * 1000)
            } else {
                pingError = "Offline"
            }
        } catch {
            pingError = "Unreachable"
        }

        isPinging = false
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
            id: "abc123def456789012345678901234567890123456789012345678901234",
            createdAt: Date().addingTimeInterval(-86400 * 7),
            lastActivity: Date().addingTimeInterval(-3600),
            remainingBytes: 200_000,
            totalBytes: 256_000,
            unreadCount: 0,
            mnemonicChecksum: ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot"],
            customName: "Alice",
            role: .initiator,
            sendOffset: 30_000,
            peerConsumed: 26_000,
            relayURL: "https://eu.relay.ashprotocol.app",
            disappearingMessages: .fiveMinutes,
            accentColor: .purple,
            persistenceConsent: true,
            authToken: "preview-auth-token",
            burnToken: "preview-burn-token"
        ),
        onBurn: {}
    )
}
