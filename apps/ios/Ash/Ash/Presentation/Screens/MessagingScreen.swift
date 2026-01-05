//
//  MessagingScreen.swift
//  Ash
//
//  Presentation Layer - Messaging interface screen
//

import SwiftUI

struct MessagingScreen: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss

    let conversation: Conversation
    let onBurn: () -> Void
    let onRename: (String) -> Void
    let onUpdateRelayURL: (String) -> Void
    var onDismiss: (() async -> Void)?

    @State private var viewModel: MessagingViewModel?
    @State private var isShowingBurnConfirmation = false
    @State private var isShowingRename = false
    @State private var renameText = ""
    @State private var isShowingSettings = false
    @State private var isShowingInfo = false

    var body: some View {
        Group {
            if let vm = viewModel {
                MessagingContent(viewModel: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(conversation.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isShowingInfo = true
                    } label: {
                        Label("Info", systemImage: "info.circle")
                    }

                    Button {
                        renameText = conversation.customName ?? ""
                        isShowingRename = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }

                    Divider()

                    Button(role: .destructive) {
                        isShowingBurnConfirmation = true
                    } label: {
                        Label("Burn Conversation", systemImage: "flame.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename Conversation", isPresented: $isShowingRename) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                onRename(renameText)
            }
        } message: {
            Text("Enter a custom name or leave empty to use mnemonic words")
        }
        .sheet(isPresented: $isShowingBurnConfirmation) {
            BurnConfirmationView(
                burnType: .conversation(name: conversation.displayName),
                onConfirm: {
                    isShowingBurnConfirmation = false
                    onBurn()
                },
                onCancel: {
                    isShowingBurnConfirmation = false
                }
            )
        }
        .sheet(isPresented: $isShowingSettings) {
            ConversationSettingsSheet(
                conversation: viewModel?.currentConversation ?? conversation,
                onSave: { url in
                    onUpdateRelayURL(url)
                    isShowingSettings = false
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $isShowingInfo) {
            ConversationInfoScreen(
                conversation: viewModel?.currentConversation ?? conversation
            )
            .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewModel?.isShowingBurnedScreen ?? false },
            set: { viewModel?.isShowingBurnedScreen = $0 }
        )) {
            BurnedConversationScreen(
                conversationName: conversation.displayName,
                onDismiss: {
                    viewModel?.isShowingBurnedScreen = false
                    dismiss()
                }
            )
        }
        .task {
            viewModel = MessagingViewModel(conversation: conversation, dependencies: dependencies)
            await viewModel?.onAppear()
        }
        .onDisappear {
            // Use Task to handle async cleanup
            Task {
                await viewModel?.onDisappear()
                await onDismiss?()
            }
        }
    }
}

// MARK: - Conversation Relay Settings Sheet

private struct ConversationSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let conversation: Conversation
    let onSave: (String) -> Void

    @State private var relayURL: String = ""
    @State private var isTestingConnection: Bool = false
    @State private var connectionTestResult: SettingsScreen.ConnectionTestResult?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Server URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("https://relay.example.com", text: $relayURL)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }

                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if let result = connectionTestResult {
                                switch result {
                                case .success:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                case .failure:
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    .disabled(isTestingConnection || relayURL.isEmpty)

                    if let result = connectionTestResult {
                        switch result {
                        case .success(let version):
                            Text("Connected - \(version)")
                                .font(.caption)
                                .foregroundStyle(.green)
                        case .failure(let error):
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Relay Server")
                } footer: {
                    Text("Messages are stored in server RAM for \(MessageTTL.displayName) and deleted on delivery or expiry.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(relayURL)
                    }
                    .disabled(relayURL.isEmpty)
                }
            }
            .onAppear {
                relayURL = conversation.relayURL
            }
        }
    }

    private func testConnection() async {
        isTestingConnection = true
        connectionTestResult = nil

        defer { isTestingConnection = false }

        guard let url = URL(string: relayURL)?.appendingPathComponent("health") else {
            connectionTestResult = .failure(error: "Invalid URL")
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                connectionTestResult = .failure(error: "Server returned error")
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = json["version"] as? String {
                connectionTestResult = .success(version: "v\(version)")
            } else {
                connectionTestResult = .success(version: "OK")
            }
        } catch {
            connectionTestResult = .failure(error: error.localizedDescription)
        }
    }
}

// MARK: - Content

private struct MessagingContent: View {
    @Bindable var viewModel: MessagingViewModel
    @FocusState private var isInputFocused: Bool
    @State private var selectedMessageForInfo: Message?

    var body: some View {
        VStack(spacing: 0) {
            // Peer burned warning
            if viewModel.peerBurned {
                PeerBurnedBanner()
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        PadUsageHeaderView(
                            conversation: viewModel.currentConversation,
                            isConnected: viewModel.isConnected,
                            relayError: viewModel.relayError
                        )
                        .padding(.top, Spacing.md)

                        if viewModel.messages.isEmpty {
                            ContentUnavailableView(
                                "No Messages",
                                systemImage: "bubble.left.and.bubble.right",
                                description: Text("Messages are ephemeral and disappear after viewing")
                            )
                            .padding(.top, Spacing.xxl)
                        } else {
                            ForEach(viewModel.messages) { message in
                                MessageBubbleView(
                                    message: message,
                                    onRetry: {
                                        if case .failed = message.deliveryStatus {
                                            Task { await viewModel.retryMessage(message) }
                                        }
                                    },
                                    onInfo: {
                                        selectedMessageForInfo = message
                                    }
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }

            // Input - disabled if peer burned
            if !viewModel.peerBurned {
                MessageInputView(
                    text: $viewModel.messageText,
                    isFocused: $isInputFocused,
                    canSend: viewModel.canSendMessage,
                    currentBytes: viewModel.currentMessageBytes,
                    isApproachingLimit: viewModel.isApproachingLimit,
                    isMessageTooLarge: viewModel.isMessageTooLarge,
                    formattedSize: viewModel.formattedMessageSize,
                    sizeError: viewModel.messageSizeError,
                    locationError: viewModel.locationError,
                    isGettingLocation: viewModel.isGettingLocation,
                    onSend: {
                        Task { await viewModel.sendMessage() }
                    },
                    onSendLocation: {
                        Task { await viewModel.sendLocation() }
                    }
                )
            }
        }
        .sheet(item: $selectedMessageForInfo) { message in
            MessageDetailView(message: message)
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Peer Burned Banner

private struct PeerBurnedBanner: View {
    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.white)
            Text("This conversation has been burned")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.ashDanger)
    }
}

// MARK: - Pad Usage Header

private struct PadUsageHeaderView: View {
    let conversation: Conversation
    var isConnected: Bool = false
    var relayError: String?

    var body: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Color.ashSecure)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(conversation.formattedRemaining) remaining")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.primary)

                    DualUsageBar(
                        myUsage: conversation.myUsagePercentage,
                        peerUsage: conversation.peerUsagePercentage,
                        height: 4
                    )
                    .frame(width: 80)
                }

                Spacer()

                // Relay status indicator
                RelayStatusIndicator(isConnected: isConnected, error: relayError)

                MnemonicDisplay(words: Array(conversation.mnemonicChecksum.prefix(3)))
            }
        }
        .padding(Spacing.sm)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
    }
}

// MARK: - Relay Status Indicator

private struct RelayStatusIndicator: View {
    let isConnected: Bool
    let error: String?

    var body: some View {
        HStack(spacing: 4) {
            if let error = error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption2)
                    .help(error)
            } else if isConnected {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                    .font(.caption2)
            } else {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .frame(width: 20)
    }
}

// MARK: - Message Bubble

private struct MessageBubbleView: View {
    let message: Message
    let onRetry: (() -> Void)?
    let onInfo: (() -> Void)?

    init(message: Message, onRetry: (() -> Void)? = nil, onInfo: (() -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
        self.onInfo = onInfo
    }

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 60) }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 4) {
                bubbleContent
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
                    .contextMenu {
                        Button {
                            onInfo?()
                        } label: {
                            Label("Info", systemImage: "info.circle")
                        }

                        Button {
                            copyToClipboard(message.content)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        if case .failed = message.deliveryStatus {
                            Button {
                                onRetry?()
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                        }
                    }

                // Status row
                HStack(spacing: 6) {
                    if let expiresAt = message.expiresAt {
                        ExpiryIndicatorView(expiresAt: expiresAt)
                    }
                    Text(message.formattedTime)
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)

                    // Delivery status for outgoing messages
                    if message.isOutgoing {
                        DeliveryStatusView(status: message.deliveryStatus, onRetry: onRetry)
                    }
                }
            }

            if !message.isOutgoing { Spacer(minLength: 60) }
        }
        .accessibilityElement(children: .combine)
    }

    private func copyToClipboard(_ content: MessageContent) {
        switch content {
        case .text(let text):
            UIPasteboard.general.string = text
        case .location(let lat, let lon):
            UIPasteboard.general.string = "\(lat), \(lon)"
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        Group {
            switch message.content {
            case .text(let text):
                Text(text)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)

            case .location(let lat, let lon):
                LocationBubbleContent(
                    latitude: lat,
                    longitude: lon,
                    isOutgoing: message.isOutgoing
                )
            }
        }
        .background(message.isOutgoing ? Color.ashSecure : Color(uiColor: .secondarySystemBackground))
        .foregroundStyle(message.isOutgoing ? Color.white : Color.primary)
    }
}

// MARK: - Location Bubble Content

private struct LocationBubbleContent: View {
    let latitude: Double
    let longitude: Double
    let isOutgoing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Header
            HStack(spacing: Spacing.xs) {
                Image(systemName: "location.fill")
                    .font(.caption)
                Text(L10n.Messaging.location)
                    .font(.caption.bold())
            }

            // Coordinates
            Text(String(format: "%.6f, %.6f", latitude, longitude))
                .font(.system(.caption, design: .monospaced))

            // Open in Maps button
            Button {
                openInMaps()
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "map.fill")
                        .font(.caption2)
                    Text("Open in Maps")
                        .font(.caption2.bold())
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background(
                    Capsule()
                        .fill(isOutgoing ? Color.white.opacity(0.2) : Color.ashSecure.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private func openInMaps() {
        // Use Apple Maps URL scheme
        let urlString = "maps://?ll=\(latitude),\(longitude)&q=Shared%20Location"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Delivery Status View

private struct DeliveryStatusView: View {
    let status: DeliveryStatus
    let onRetry: (() -> Void)?

    var body: some View {
        switch status {
        case .sending:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)

        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondary)

        case .failed(let reason):
            Button {
                onRetry?()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ashDanger)

                    if reason != nil {
                        Text(L10n.Error.relayError)
                            .font(.caption2)
                            .foregroundStyle(Color.ashDanger)
                    }
                }
            }
            .buttonStyle(.plain)

        case .none:
            EmptyView()
        }
    }
}

// MARK: - Expiry Indicator

private struct ExpiryIndicatorView: View {
    let expiresAt: Date
    @State private var remainingTime: TimeInterval = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Estimate initial TTL from the message creation time
    /// Uses common TTL values to determine the total duration
    private var estimatedTotalTime: TimeInterval {
        let elapsed = Date().timeIntervalSince(expiresAt.addingTimeInterval(-remainingTime))
        let total = elapsed + remainingTime
        // Round to nearest common TTL value for progress calculation
        let commonTTLs: [TimeInterval] = [60, 300, 1800, 3600, 21600, 86400, 172800, 604800]
        return commonTTLs.first { $0 >= total * 0.9 } ?? total
    }

    private var progress: Double {
        guard estimatedTotalTime > 0 else { return 0 }
        return max(0, min(1, remainingTime / estimatedTotalTime))
    }

    private var indicatorColor: Color {
        if remainingTime < 60 {
            return Color.ashDanger
        } else if remainingTime < 300 {
            return Color.ashWarning
        }
        return Color.secondary
    }

    private var ringColor: Color {
        if progress < 0.1 {
            return Color.ashDanger
        } else if progress < 0.25 {
            return Color.ashWarning
        }
        return Color.ashSecure.opacity(0.6)
    }

    var body: some View {
        HStack(spacing: 4) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
            }
            .frame(width: 14, height: 14)

            // Human readable time
            Text(formatHumanReadable(remainingTime))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(indicatorColor)
        }
        .onAppear {
            remainingTime = max(0, expiresAt.timeIntervalSinceNow)
        }
        .onReceive(timer) { _ in
            remainingTime = max(0, expiresAt.timeIntervalSinceNow)
        }
        .accessibilityLabel("Expires in \(formatHumanReadable(remainingTime))")
    }

    private func formatHumanReadable(_ seconds: TimeInterval) -> String {
        if seconds <= 0 {
            return "expired"
        } else if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            let mins = Int(seconds) / 60
            let secs = Int(seconds) % 60
            if secs == 0 || mins >= 5 {
                return "\(mins)m"
            }
            return "\(mins)m \(secs)s"
        } else if seconds < 86400 {
            let hours = Int(seconds) / 3600
            let mins = (Int(seconds) % 3600) / 60
            if mins == 0 || hours >= 6 {
                return "\(hours)h"
            }
            return "\(hours)h \(mins)m"
        } else {
            let days = Int(seconds) / 86400
            let hours = (Int(seconds) % 86400) / 3600
            if hours == 0 || days >= 2 {
                return "\(days)d"
            }
            return "\(days)d \(hours)h"
        }
    }
}

// MARK: - Message Input

private struct MessageInputView: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let canSend: Bool
    let currentBytes: Int
    let isApproachingLimit: Bool
    let isMessageTooLarge: Bool
    let formattedSize: String
    let sizeError: String?
    let locationError: String?
    let isGettingLocation: Bool
    let onSend: () -> Void
    let onSendLocation: () -> Void

    /// Show size indicator when message is > 1KB
    private var showSizeIndicator: Bool {
        currentBytes > 1024
    }

    /// Color for the size indicator
    private var sizeIndicatorColor: Color {
        if isMessageTooLarge {
            return Color.ashDanger
        } else if isApproachingLimit {
            return Color.ashWarning
        }
        return Color.secondary
    }

    /// Combined error message (size or location)
    private var errorMessage: String? {
        sizeError ?? locationError
    }

    var body: some View {
        VStack(spacing: 0) {
            // Error banner
            if let error = errorMessage {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(Color.ashDanger)
            }

            HStack(spacing: Spacing.sm) {
                // Location button
                Button(action: onSendLocation) {
                    if isGettingLocation {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "location.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.ashSecure)
                            .frame(width: 28, height: 28)
                    }
                }
                .disabled(isGettingLocation)
                .accessibilityLabel("Share location")

                VStack(alignment: .trailing, spacing: 2) {
                    TextField("Message", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(isMessageTooLarge ? Color.ashDanger : Color.clear, lineWidth: 2)
                                )
                        )
                        .lineLimit(1...5)
                        .focused(isFocused)

                    // Size indicator
                    if showSizeIndicator {
                        HStack(spacing: 4) {
                            Text(formattedSize)
                            Text("/")
                            Text("\(MessageLimits.maxMessageKB) KB")
                        }
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(sizeIndicatorColor)
                        .padding(.trailing, Spacing.xs)
                    }
                }

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(canSend ? Color.ashSecure : Color.secondary)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send message")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Material.bar)
        }
    }
}
