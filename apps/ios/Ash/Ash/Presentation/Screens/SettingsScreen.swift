//
//  SettingsScreen.swift
//  Ash
//
//  App settings
//

import SwiftUI

struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var dependencies

    @Bindable var lockViewModel: AppLockViewModel
    let onBurnAll: () -> Void
    let onRelaySettingsChanged: () -> Void

    @State private var isShowingBurnAllConfirmation = false
    @State private var isShowingEmergencyBurn = false
    @State private var biometricEnabled = false
    @State private var defaultRelayURL = ""
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?

    enum ConnectionTestResult {
        case success(version: String)
        case failure(error: String)
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Security
                securitySection

                // MARK: - Relay
                relaySection

                // MARK: - About
                aboutSection

                // MARK: - Danger Zone
                dangerSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Burn All Conversations?",
                isPresented: $isShowingBurnAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Burn All", role: .destructive) {
                    onBurnAll()
                    dismiss()
                }
            } message: {
                Text("This will permanently destroy all conversations and encryption pads. This cannot be undone.")
            }
            .onAppear {
                biometricEnabled = lockViewModel.isBiometricLockEnabled
                defaultRelayURL = dependencies.settingsService.relayServerURL
            }
            .sheet(isPresented: $isShowingEmergencyBurn) {
                BurnConfirmationView(
                    burnType: .all,
                    onConfirm: {
                        isShowingEmergencyBurn = false
                        onBurnAll()
                        dismiss()
                    },
                    onCancel: {
                        isShowingEmergencyBurn = false
                    }
                )
            }
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section {
            if lockViewModel.canUseBiometrics {
                Toggle(isOn: $biometricEnabled) {
                    Label(lockViewModel.biometricType.displayName, systemImage: lockViewModel.biometricType.iconName)
                }
                .onChange(of: biometricEnabled) { _, newValue in
                    Task {
                        if newValue {
                            let success = await lockViewModel.enableBiometricLock()
                            if !success { biometricEnabled = false }
                        } else {
                            lockViewModel.disableBiometricLock()
                        }
                    }
                }

                if lockViewModel.isBiometricLockEnabled {
                    Toggle(isOn: Binding(
                        get: { lockViewModel.lockOnBackground },
                        set: { lockViewModel.lockOnBackground = $0 }
                    )) {
                        Label("Lock on Background", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        } header: {
            Text("Security")
        } footer: {
            Text("Protect your conversations with biometric authentication.")
        }
    }

    // MARK: - Relay Section

    private var relaySection: some View {
        Section {
            LabeledContent {
                TextField("Server URL", text: $defaultRelayURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .onChange(of: defaultRelayURL) { _, _ in
                        connectionTestResult = nil
                    }
            } label: {
                Text("Server")
            }

            Button {
                saveDefaultRelayURL()
            } label: {
                HStack {
                    Text("Save")
                    Spacer()
                    if defaultRelayURL != dependencies.settingsService.relayServerURL {
                        Text("Modified")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .disabled(defaultRelayURL.isEmpty || defaultRelayURL == dependencies.settingsService.relayServerURL)

            if defaultRelayURL != SettingsService.defaultRelayURL {
                Button {
                    defaultRelayURL = SettingsService.defaultRelayURL
                    saveDefaultRelayURL()
                } label: {
                    HStack {
                        Text("Reset to Default")
                        Spacer()
                        Text(SettingsService.defaultRelayURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Button {
                Task { await testConnection() }
            } label: {
                HStack {
                    Text("Test Connection")
                    Spacer()
                    if isTestingConnection {
                        ProgressView()
                    } else if let result = connectionTestResult {
                        switch result {
                        case .success(let version):
                            Text(version)
                                .foregroundStyle(.green)
                        case .failure:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .disabled(isTestingConnection || defaultRelayURL.isEmpty)
        } header: {
            Text("Relay Server")
        } footer: {
            Text("Default server URL for new conversations. Message TTL is configured per-conversation.")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: "1.0.0")
            LabeledContent("Encryption", value: "One-Time Pad")

            NavigationLink {
                SecurityInfoView()
            } label: {
                Text("Security Model")
            }

            NavigationLink {
                PrivacyInfoView()
            } label: {
                Text("Privacy")
            }
        }
    }

    // MARK: - Danger Section

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                isShowingEmergencyBurn = true
            } label: {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Label("Emergency Burn All", systemImage: "flame.fill")
                            .font(.headline)
                        Text("Destroy all conversations instantly")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        } header: {
            Label("Danger Zone", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.ashDanger)
        } footer: {
            Text("Emergency burn immediately destroys all conversations, encryption pads, and messages on this device. This cannot be undone.")
        }
    }

    // MARK: - Helpers

    private func saveDefaultRelayURL() {
        var settings = dependencies.settingsService
        settings.relayServerURL = defaultRelayURL
        connectionTestResult = nil
        onRelaySettingsChanged()
    }

    private func testConnection() async {
        isTestingConnection = true
        connectionTestResult = nil
        defer { isTestingConnection = false }

        guard let url = URL(string: defaultRelayURL)?.appendingPathComponent("health") else {
            connectionTestResult = .failure(error: "Invalid URL")
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                connectionTestResult = .failure(error: "Server error")
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

// MARK: - Security Info

private struct SecurityInfoView: View {
    var body: some View {
        List {
            Section {
                InfoRow(
                    title: "One-Time Pad",
                    description: "Mathematically proven unbreakable encryption. Each byte is used exactly once."
                )
            }

            Section {
                InfoRow(
                    title: "Offline Key Exchange",
                    description: "Keys are exchanged in person via QR codes. No keys touch the network."
                )
            }

            Section {
                InfoRow(
                    title: "Human Verification",
                    description: "Both devices display matching words that users verify verbally."
                )
            }

            Section {
                InfoRow(
                    title: "Ephemeral Messages",
                    description: "Messages are never stored on disk and disappear after viewing."
                )
            }

            Section {
                InfoRow(
                    title: "Zero-Trust Backend",
                    description: "The server only sees encrypted blobs. Even if compromised, content is unrecoverable."
                )
            }
        }
        .navigationTitle("Security Model")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct InfoRow: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Privacy Info

private struct PrivacyInfoView: View {
    var body: some View {
        List {
            Section("No Accounts") {
                CheckItem("No phone number required")
                CheckItem("No email required")
                CheckItem("No identity verification")
            }

            Section("No Tracking") {
                CheckItem("No analytics")
                CheckItem("No crash reporting")
                CheckItem("No advertising")
            }

            Section("No Persistence") {
                CheckItem("Messages never written to disk")
                CheckItem("No message history")
                CheckItem("No cloud backup")
            }

            Section("Minimal Network") {
                CheckItem("Keys exchanged offline")
                CheckItem("Backend sees only encrypted data")
                CheckItem("No metadata collection")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CheckItem: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: "checkmark")
            .foregroundStyle(.primary)
    }
}


#Preview {
    SettingsScreen(lockViewModel: AppLockViewModel(), onBurnAll: {}, onRelaySettingsChanged: {})
}
