//
//  InitiatorCeremonyViewModel.swift
//  Ash
//
//  Presentation Layer - Initiator ceremony flow (generates pad, displays QR)
//  Uses fountain codes for reliable QR transfer
//

import SwiftUI
import UIKit

@MainActor
@Observable
final class InitiatorCeremonyViewModel {

    private let dependencies: Dependencies

    // MARK: - State

    private(set) var phase: CeremonyPhase = .selectingPadSize
    private(set) var generatedPadBytes: [UInt8]?
    private(set) var fountainGenerator: FountainFrameGenerator?
    private(set) var preGeneratedQRImages: [UIImage] = []
    private(set) var sourceBlockCount: Int = 0

    // Configuration state
    var selectedPadSize: PadSize = .medium
    var entropyProgress: Double = 0.0
    var collectedEntropy: [UInt8] = []

    var isPassphraseEnabled: Bool = false
    var passphrase: String = ""

    var conversationName: String = ""

    /// Relay server URL for this conversation
    var selectedRelayURL: String = ""

    /// Connection test state
    private(set) var isTestingConnection: Bool = false
    private(set) var connectionTestResult: RelayConnectionResult?

    enum RelayConnectionResult: Equatable {
        case success(version: String)
        case failure(error: String)
    }

    /// Server retention - how long messages wait on server before expiring
    var serverRetention: MessageRetention = .oneDay

    /// Disappearing messages setting (client-side display TTL)
    var disappearingMessages: DisappearingMessages = .off

    var consent: ConsentState = ConsentState()

    // Display cycling
    private var displayTimer: Timer?
    private var currentDisplayIndex: Int = 0

    // MARK: - Constants

    /// Block size for fountain encoding (1500 bytes + 16 header, base64 ~2021 chars, fits Version 23-24 QR)
    private let fountainBlockSize: UInt32 = 1500
    private let qrCodeSize: CGFloat = 380
    /// How many extra blocks to pre-generate beyond source count (for redundancy)
    private let redundancyBlocks: Int = 20
    /// Frame display interval in seconds
    private let frameDisplayInterval: TimeInterval = 0.15

    // MARK: - Initialization

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        self.selectedRelayURL = dependencies.settingsService.relayServerURL
        Log.debug(.ceremony, "Initiator ceremony view model initialized")
    }

    // MARK: - Computed Properties

    var isPassphraseValid: Bool {
        guard isPassphraseEnabled else { return true }
        guard !passphrase.isEmpty else { return false }
        return validatePassphrase(passphrase: passphrase)
    }

    var isRelayURLValid: Bool {
        guard let url = URL(string: selectedRelayURL) else { return false }
        return url.scheme == "https" || url.scheme == "http"
    }

    var isConsentComplete: Bool {
        consent.allConfirmed
    }

    var currentFrameIndex: Int {
        currentDisplayIndex
    }

    var totalFrameCount: Int {
        sourceBlockCount
    }

    // MARK: - Pad Size Selection

    func selectPadSize(_ size: PadSize) {
        dependencies.hapticService.selection()
        selectedPadSize = size
        Log.debug(.ceremony, "Pad size selected: \(size.displayName) (\(size.bytes) bytes)")
    }

    func proceedToOptions() {
        dependencies.hapticService.medium()
        Log.debug(.ceremony, "Proceeding to options phase")
        phase = .configuringOptions
    }

    // MARK: - Options & Consent

    func proceedToConsent() {
        dependencies.hapticService.medium()
        Log.debug(.ceremony, "Proceeding to consent phase")
        phase = .confirmingConsent
    }

    func testRelayConnection() async {
        isTestingConnection = true
        connectionTestResult = nil
        defer { isTestingConnection = false }

        guard let url = URL(string: selectedRelayURL)?.appendingPathComponent("health") else {
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
                dependencies.hapticService.success()
            } else {
                connectionTestResult = .success(version: "OK")
                dependencies.hapticService.success()
            }
        } catch {
            connectionTestResult = .failure(error: error.localizedDescription)
            dependencies.hapticService.error()
        }
    }

    func clearConnectionTest() {
        connectionTestResult = nil
    }

    func confirmConsent() {
        guard isConsentComplete else { return }
        dependencies.hapticService.success()
        Log.info(.ceremony, "Consent confirmed, proceeding to entropy collection")
        phase = .collectingEntropy
    }

    // MARK: - Entropy Collection

    func addEntropy(from point: CGPoint) {
        let x = UInt8(truncatingIfNeeded: Int(point.x * 256))
        let y = UInt8(truncatingIfNeeded: Int(point.y * 256))
        let timestamp = UInt8(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000))

        collectedEntropy.append(contentsOf: [x, y, timestamp])
        entropyProgress = min(1.0, Double(collectedEntropy.count) / 500.0)

        if entropyProgress >= 1.0 {
            Log.info(.ceremony, "Entropy collection complete: \(collectedEntropy.count) bytes")
            Task { await generatePad() }
        }
    }

    // MARK: - Pad Generation with Fountain Codes

    func generatePad() async {
        dependencies.hapticService.success()
        phase = .generatingPad

        let entropy = collectedEntropy
        let padSizeBytes = Int(selectedPadSize.bytes)
        Log.info(.ceremony, "Generating pad: \(padSizeBytes) bytes from \(entropy.count) entropy bytes")

        do {
            let padBytes = try await dependencies.performCeremonyUseCase.generatePadBytes(
                entropy: entropy,
                sizeBytes: padSizeBytes
            )
            generatedPadBytes = padBytes

            let disappearingSeconds = UInt32(disappearingMessages.seconds ?? 0)
            let metadata = CeremonyMetadataSwift(
                ttlSeconds: serverRetention.seconds,
                disappearingMessagesSeconds: disappearingSeconds,
                relayURL: selectedRelayURL
            )

            Log.debug(.ceremony, "Creating fountain generator: serverTTL=\(serverRetention.displayName), disappearing=\(disappearingMessages.displayName), passphrase=\(isPassphraseEnabled)")

            let passphraseToUse = isPassphraseEnabled ? passphrase : nil
            let generator = try await dependencies.performCeremonyUseCase.createFountainGenerator(
                padBytes: padBytes,
                metadata: metadata,
                blockSize: fountainBlockSize,
                passphrase: passphraseToUse
            )

            fountainGenerator = generator
            sourceBlockCount = Int(generator.sourceCount())

            Log.info(.ceremony, "Fountain generator ready: \(sourceBlockCount) source blocks, block size: \(generator.blockSize())")
            await preGenerateQRCodes()
        } catch {
            Log.error(.ceremony, "Pad generation failed: \(error)")
            phase = .failed(.qrGenerationFailed)
        }
    }

    private func preGenerateQRCodes() async {
        guard let generator = fountainGenerator else {
            Log.error(.ceremony, "No fountain generator available")
            phase = .failed(.qrGenerationFailed)
            return
        }

        // Pre-generate source blocks + some redundancy blocks
        let totalToGenerate = sourceBlockCount + redundancyBlocks
        Log.info(.ceremony, "Pre-generating \(totalToGenerate) QR codes at \(Int(qrCodeSize))px")
        phase = .generatingQRCodes(progress: 0, total: totalToGenerate)
        preGeneratedQRImages = []
        preGeneratedQRImages.reserveCapacity(totalToGenerate)

        for index in 0..<totalToGenerate {
            let frameBytes = generator.generateFrame(index: UInt32(index))
            let frameData = Data(frameBytes)

            if let image = QRCodeGenerator.generate(from: frameData, size: qrCodeSize) {
                preGeneratedQRImages.append(image)
                let progress = Double(index + 1) / Double(totalToGenerate)
                phase = .generatingQRCodes(progress: progress, total: totalToGenerate)
            } else {
                Log.error(.ceremony, "QR generation failed at frame \(index)/\(totalToGenerate)")
                phase = .failed(.qrGenerationFailed)
                return
            }

            if index % 10 == 0 {
                await Task.yield()
            }
        }

        Log.info(.ceremony, "QR generation complete: \(totalToGenerate) codes ready")
        dependencies.hapticService.success()
        phase = .transferring(currentFrame: 0, totalFrames: sourceBlockCount)
        startDisplayCycling()
    }

    // MARK: - QR Display Cycling

    private func startDisplayCycling() {
        currentDisplayIndex = 0
        displayTimer = Timer.scheduledTimer(withTimeInterval: frameDisplayInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceFrame()
            }
        }
    }

    private func advanceFrame() {
        guard !preGeneratedQRImages.isEmpty else { return }
        currentDisplayIndex = (currentDisplayIndex + 1) % preGeneratedQRImages.count
        if case .transferring = phase {
            phase = .transferring(currentFrame: currentDisplayIndex % sourceBlockCount, totalFrames: sourceBlockCount)
        }
    }

    func stopDisplayCycling() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    func currentQRImage() -> UIImage? {
        guard currentDisplayIndex < preGeneratedQRImages.count else { return nil }
        return preGeneratedQRImages[currentDisplayIndex]
    }

    func currentFrameData() -> Data? {
        guard let generator = fountainGenerator else { return nil }
        let frameBytes = generator.generateFrame(index: UInt32(currentDisplayIndex))
        return Data(frameBytes)
    }

    func finishSending() {
        Log.info(.ceremony, "Sender finished, proceeding to verification")
        stopDisplayCycling()
        Task { await proceedToVerification() }
    }

    // MARK: - Verification

    private func proceedToVerification() async {
        guard let padBytes = generatedPadBytes else {
            Log.error(.ceremony, "No pad bytes for verification")
            phase = .failed(.padReconstructionFailed)
            return
        }

        Log.info(.ceremony, "Generating verification mnemonic for \(padBytes.count) byte pad")
        let mnemonic = await dependencies.performCeremonyUseCase.generateMnemonic(from: padBytes)
        phase = .verifying(mnemonic: mnemonic)
    }

    func confirmVerification() async -> Conversation? {
        dependencies.hapticService.success()

        guard let padBytes = generatedPadBytes,
              case .verifying = phase else {
            Log.error(.ceremony, "Invalid state for verification confirmation")
            phase = .failed(.checksumMismatch)
            return nil
        }

        do {
            let customName = conversationName.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = customName.isEmpty ? nil : customName

            Log.info(.ceremony, "Initiator finalizing ceremony with relay: \(selectedRelayURL)")

            let mnemonic = generateMnemonic(padBytes: padBytes)
            let conversation = try await dependencies.performCeremonyUseCase.finalizeCeremony(
                padBytes: padBytes,
                mnemonic: mnemonic,
                role: .initiator,
                relayURL: selectedRelayURL,
                customName: finalName,
                disappearingMessages: disappearingMessages
            )

            Log.info(.ceremony, "Ceremony completed: conversation \(conversation.id.prefix(8)), role=initiator, pad=\(padBytes.count) bytes")
            phase = .completed(conversation: conversation)
            return conversation
        } catch {
            Log.error(.ceremony, "Finalization failed: \(error)")
            phase = .failed(.padReconstructionFailed)
            return nil
        }
    }

    func rejectVerification() {
        Log.warning(.ceremony, "Verification rejected by user")
        dependencies.hapticService.error()
        phase = .failed(.checksumMismatch)
    }

    // MARK: - Reset & Cancel

    func reset() {
        Log.debug(.ceremony, "Resetting initiator ceremony state")
        stopDisplayCycling()
        phase = .selectingPadSize
        generatedPadBytes = nil
        fountainGenerator = nil
        preGeneratedQRImages = []
        sourceBlockCount = 0
        collectedEntropy = []
        entropyProgress = 0
        consent = ConsentState()
        currentDisplayIndex = 0
        selectedRelayURL = dependencies.settingsService.relayServerURL
        connectionTestResult = nil
    }

    func cancel() {
        Log.info(.ceremony, "Ceremony cancelled")
        stopDisplayCycling()
        phase = .failed(.cancelled)
    }

    nonisolated deinit {
        // Timer cleanup is handled by stopDisplayCycling() called in reset()/cancel()
        // Timer will be invalidated automatically when deallocated if still running
    }
}
