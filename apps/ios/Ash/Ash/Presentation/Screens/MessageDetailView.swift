//
//  MessageDetailView.swift
//  Ash
//
//  Message details - Full screen info view matching ConversationInfoScreen design
//

import SwiftUI

struct MessageDetailView: View {
    let message: Message
    var accentColor: Color = .ashAccent
    var onExtendTTL: (() async -> Bool)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isExtendingTTL = false
    @State private var extendTTLSuccess: Bool?
    @State private var showCopiedFeedback = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    headerSection

                    // Verification Status (for authenticated messages)
                    if message.authTag != nil || message.isOutgoing {
                        verificationSection
                            .padding(.top, 12)
                    }

                    // Content Section
                    contentSection
                        .padding(.top, 12)

                    // Timing Section
                    timingSection
                        .padding(.top, 12)

                    // Server Status Section (for outgoing awaiting delivery)
                    if message.isOutgoing && message.isAwaitingDelivery {
                        serverSection
                            .padding(.top, 12)
                    }

                    // Technical Details Section
                    technicalSection
                        .padding(.top, 12)

                    // Actions Section
                    actionsSection
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Message Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(accentColor)
                }
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

                Image(systemName: message.isOutgoing ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(accentColor)
            }

            VStack(spacing: 4) {
                Text(message.isOutgoing ? "Sent Message" : "Received Message")
                    .font(.title2.bold())

                // Message type tag
                HStack(spacing: 6) {
                    Image(systemName: contentIcon)
                        .font(.caption)
                    Text(contentTypeName)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill), in: Capsule())
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Verification Section

    private var verificationSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: verificationIcon)
                    .font(.title3)
                    .foregroundStyle(verificationColor)
                    .frame(width: 32)
                Text("Verification")
                    .font(.subheadline.bold())
                Spacer()
            }
            .padding(16)

            Divider().padding(.leading, 56)

            // Verification status
            HStack {
                Text("Status")
                    .font(.subheadline)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: verificationIcon)
                        .font(.caption)
                    Text(verificationStatusText)
                        .font(.subheadline)
                }
                .foregroundStyle(verificationColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().padding(.leading, 56)

            // Verification explanation
            Text(verificationExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: contentIcon)
                    .font(.title3)
                    .foregroundStyle(accentColor)
                    .frame(width: 32)
                Text("Content")
                    .font(.subheadline.bold())
                Spacer()

                // Content size
                Text(formatBytes(message.content.byteCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider().padding(.leading, 56)

            // Content display
            Group {
                switch message.content {
                case .text(let text):
                    if message.isContentWiped {
                        HStack {
                            Image(systemName: "eye.slash.fill")
                                .foregroundStyle(.secondary)
                            Text("[Message Expired]")
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    } else {
                        Text(text)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }

                case .location(let lat, let lon):
                    VStack(spacing: 12) {
                        InfoRow(label: "Latitude", value: String(format: "%.6f", lat))
                        Divider().padding(.leading, 56)
                        InfoRow(label: "Longitude", value: String(format: "%.6f", lon))

                        Divider()

                        Button {
                            openInMaps(lat: lat, lon: lon)
                        } label: {
                            HStack {
                                Image(systemName: "map.fill")
                                Text("Open in Maps")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: - Timing Section

    private var timingSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "clock")
                    .font(.title3)
                    .foregroundStyle(accentColor)
                    .frame(width: 32)
                Text("Timing")
                    .font(.subheadline.bold())
                Spacer()
            }
            .padding(16)

            Divider().padding(.leading, 56)

            // Timestamp
            InfoRow(
                label: message.isOutgoing ? "Sent" : "Received",
                value: message.timestamp.formatted(date: .abbreviated, time: .standard)
            )

            Divider().padding(.leading, 56)

            // Relative time
            InfoRow(label: "Time Ago", value: message.timestamp.formatted(.relative(presentation: .named)))

            // Local expiry (disappearing messages)
            if let expiresAt = message.expiresAt {
                Divider().padding(.leading, 56)
                HStack {
                    Text("Disappears")
                        .font(.subheadline)
                    Spacer()
                    if message.isExpired {
                        Text("Expired")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    } else {
                        Text(expiresAt, style: .relative)
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: - Server Status Section

    private var serverSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.title3)
                    .foregroundStyle(accentColor)
                    .frame(width: 32)
                Text("Server Status")
                    .font(.subheadline.bold())
                Spacer()
            }
            .padding(16)

            Divider().padding(.leading, 56)

            // Delivery status
            HStack {
                Text("Delivery")
                    .font(.subheadline)
                Spacer()
                deliveryStatusView
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Server expiry
            if let serverExpiresAt = message.serverExpiresAt {
                Divider().padding(.leading, 56)
                HStack {
                    Text("Server TTL")
                        .font(.subheadline)
                    Spacer()
                    if serverExpiresAt < Date() {
                        Text("Expired")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    } else {
                        Text(serverExpiresAt, style: .relative)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Extend TTL button
                if onExtendTTL != nil && serverExpiresAt > Date() {
                    Divider().padding(.leading, 56)

                    Button {
                        Task {
                            isExtendingTTL = true
                            extendTTLSuccess = await onExtendTTL?()
                            isExtendingTTL = false
                        }
                    } label: {
                        HStack {
                            if isExtendingTTL {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if let success = extendTTLSuccess {
                                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(success ? .green : .red)
                            } else {
                                Image(systemName: "clock.arrow.2.circlepath")
                            }
                            Text(extendTTLButtonText)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(isExtendingTTL || extendTTLSuccess != nil)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: - Technical Details Section

    private var technicalSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.title3)
                    .foregroundStyle(accentColor)
                    .frame(width: 32)
                Text("Technical Details")
                    .font(.subheadline.bold())
                Spacer()
            }
            .padding(16)

            Divider().padding(.leading, 56)

            // Message ID
            HStack {
                Text("Message ID")
                    .font(.subheadline)
                Spacer()
                Text(message.id.uuidString.prefix(8) + "...")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Sequence number
            if let sequence = message.sequence {
                Divider().padding(.leading, 56)
                HStack {
                    Text("Pad Offset")
                        .font(.subheadline)
                    Spacer()
                    Text("\(sequence)")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Blob ID (server reference)
            if let blobId = message.blobId {
                Divider().padding(.leading, 56)
                HStack {
                    Text("Blob ID")
                        .font(.subheadline)
                    Spacer()
                    Text(blobId.uuidString.prefix(8) + "...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Authentication tag (for received messages)
            if let authTag = message.authTag {
                Divider().padding(.leading, 56)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Authentication Tag")
                        .font(.subheadline)

                    Text(formatAuthTag(authTag))
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Copy content button
            Button {
                copyContent()
                showCopiedFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showCopiedFeedback = false
                }
            } label: {
                HStack {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                    Text(showCopiedFeedback ? "Copied!" : "Copy Content")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(accentColor, in: Capsule())
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Computed Properties

    private var contentIcon: String {
        switch message.content {
        case .text: return "text.bubble.fill"
        case .location: return "location.fill"
        }
    }

    private var contentTypeName: String {
        switch message.content {
        case .text: return "Text"
        case .location: return "Location"
        }
    }

    private var verificationIcon: String {
        if message.isOutgoing {
            return "arrow.up.circle.fill"
        } else if message.authTag != nil {
            return "checkmark.shield.fill"
        } else {
            return "questionmark.shield.fill"
        }
    }

    private var verificationColor: Color {
        if message.isOutgoing {
            return accentColor
        } else if message.authTag != nil {
            return .green
        } else {
            return .orange
        }
    }

    private var verificationStatusText: String {
        if message.isOutgoing {
            return "Sent by you"
        } else if message.authTag != nil {
            return "Authenticated"
        } else {
            return "Unknown"
        }
    }

    private var verificationExplanation: String {
        if message.isOutgoing {
            return "This message was encrypted and authenticated using your shared one-time pad before being sent to the relay server."
        } else if message.authTag != nil {
            return "This message was cryptographically authenticated using a 256-bit Wegman-Carter MAC. The authentication tag proves it came from your contact and was not modified in transit."
        } else {
            return "This message could not be verified. It may have been received through an older protocol version."
        }
    }

    private var extendTTLButtonText: String {
        if isExtendingTTL {
            return "Extending..."
        } else if let success = extendTTLSuccess {
            return success ? "Extended!" : "Failed"
        } else {
            return "Extend Server TTL"
        }
    }

    @ViewBuilder
    private var deliveryStatusView: some View {
        switch message.deliveryStatus {
        case .sending:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Sending...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .sent:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
                Text("On server")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .delivered:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Delivered")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }

        case .failed(let reason):
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Failed")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                if let reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .none:
            Text("—")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        }
    }

    private func copyContent() {
        switch message.content {
        case .text(let text):
            UIPasteboard.general.string = text
        case .location(let lat, let lon):
            UIPasteboard.general.string = "\(lat), \(lon)"
        }
    }

    private func openInMaps(lat: Double, lon: Double) {
        let urlString = "maps://?ll=\(lat),\(lon)&q=Shared%20Location"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    private func formatAuthTag(_ tag: [UInt8]) -> String {
        let hex = tag.map { String(format: "%02x", $0) }.joined()
        // Group into 4-character blocks separated by spaces
        var result = ""
        for (index, char) in hex.enumerated() {
            if index > 0 && index % 4 == 0 {
                result += " "
            }
            result += String(char)
        }
        return result
    }
}

// MARK: - Info Row (reusable)

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

#Preview("Outgoing") {
    MessageDetailView(
        message: Message(
            id: UUID(),
            content: .text("Hello, this is a test message with some content to show in the detail view."),
            timestamp: Date().addingTimeInterval(-300),
            isOutgoing: true,
            expiresAt: nil,
            serverExpiresAt: Date().addingTimeInterval(180),
            deliveryStatus: .sent,
            sequence: 12345,
            blobId: UUID(),
            authTag: nil
        ),
        accentColor: .purple
    )
}

#Preview("Incoming Verified") {
    MessageDetailView(
        message: Message(
            id: UUID(),
            content: .text("This is a verified incoming message."),
            timestamp: Date().addingTimeInterval(-60),
            isOutgoing: false,
            expiresAt: Date().addingTimeInterval(240),
            serverExpiresAt: nil,
            deliveryStatus: .none,
            sequence: 54321,
            blobId: UUID(),
            authTag: Array(repeating: UInt8(0xAB), count: 32)
        ),
        accentColor: .indigo
    )
}
