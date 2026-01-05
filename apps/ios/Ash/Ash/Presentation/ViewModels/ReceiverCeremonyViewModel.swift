//
//  ReceiverCeremonyViewModel.swift
//  Ash
//
//  Presentation Layer - Receiver ceremony flow (scans QR, reconstructs pad)
//  Uses fountain codes for reliable QR transfer
//
//  With fountain codes, you can scan ANY frames and complete
//  once enough unique blocks are received. No need to wait for specific frames.
//

import SwiftUI

@MainActor
@Observable
final class ReceiverCeremonyViewModel {

    private let dependencies: Dependencies

    // MARK: - State

    private(set) var phase: CeremonyPhase = .configuringReceiver
    private(set) var generatedPadBytes: [UInt8]?
    private(set) var receivedMetadata: CeremonyMetadataSwift?
    private(set) var fountainReceiver: FountainFrameReceiver?
    private(set) var sourceBlockCount: Int = 0

    // Progress tracking - stored properties to trigger @Observable updates
    private(set) var receivedFrameCount: Int = 0
    private(set) var progress: Double = 0.0

    // Configuration state
    var isPassphraseEnabled: Bool = false
    var passphrase: String = ""
    var conversationName: String = ""

    // MARK: - Initialization

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        Log.debug(.ceremony, "Receiver ceremony view model initialized")
    }

    // MARK: - Computed Properties

    var isPassphraseValid: Bool {
        guard isPassphraseEnabled else { return true }
        guard !passphrase.isEmpty else { return false }
        return validatePassphrase(passphrase: passphrase)
    }

    // MARK: - Scanning Setup

    func startScanning() {
        dependencies.hapticService.medium()
        Log.info(.ceremony, "Starting QR scan (passphrase: \(isPassphraseEnabled ? "enabled" : "disabled"))")

        // Create fountain receiver with passphrase
        let passphraseToUse = isPassphraseEnabled ? passphrase : nil
        fountainReceiver = dependencies.performCeremonyUseCase.createFountainReceiver(passphrase: passphraseToUse)

        phase = .transferring(currentFrame: 0, totalFrames: 0)
    }

    // MARK: - Frame Processing

    func processScannedFrame(_ data: Data) {
        guard let receiver = fountainReceiver else {
            Log.warning(.ceremony, "No fountain receiver available")
            return
        }

        let bytes = [UInt8](data)

        do {
            // Add frame to receiver - it handles deduplication internally
            let isComplete = try receiver.addFrame(frameBytes: bytes)
            dependencies.hapticService.light()

            // Update source count after first successful frame
            let newSourceCount = Int(receiver.sourceCount())
            if sourceBlockCount == 0 && newSourceCount > 0 {
                sourceBlockCount = newSourceCount
                Log.info(.ceremony, "Expecting ~\(sourceBlockCount) source blocks for complete decode")
            }

            // Update stored properties to trigger UI refresh
            receivedFrameCount = Int(receiver.blocksReceived())
            progress = receiver.progress()

            if receivedFrameCount % 5 == 0 {
                Log.debug(.ceremony, "Received \(receivedFrameCount) blocks, progress: \(Int(progress * 100))%")
            }

            phase = .transferring(currentFrame: receivedFrameCount, totalFrames: sourceBlockCount)

            if isComplete {
                Log.info(.ceremony, "Fountain decode complete! Used \(receivedFrameCount) blocks")
                dependencies.hapticService.success()
                Task { await reconstructAndVerify() }
            }
        } catch {
            // CRC mismatch or invalid frame - just ignore and continue scanning
            // This is expected for corrupted scans or wrong passphrase
            Log.debug(.ceremony, "Frame decode error (expected for corrupted scans): \(error)")
        }
    }

    // MARK: - Reconstruction

    private func reconstructAndVerify() async {
        guard let receiver = fountainReceiver,
              let result = receiver.getResult() else {
            Log.error(.ceremony, "Failed to get fountain decode result")
            phase = .failed(.padReconstructionFailed)
            return
        }

        Log.info(.ceremony, "Reconstructed pad: \(result.pad.count) bytes using \(result.blocksUsed) blocks")

        // Extract metadata
        let metadata = CeremonyMetadataSwift(
            ttlSeconds: result.metadata.ttlSeconds,
            disappearingMessagesSeconds: result.metadata.disappearingMessagesSeconds,
            relayURL: result.metadata.relayUrl
        )
        receivedMetadata = metadata
        generatedPadBytes = result.pad

        Log.info(.ceremony, "Decoded metadata: ttl=\(metadata.ttlSeconds)s, disappearing=\(metadata.disappearingMessagesSeconds)s")

        // Generate mnemonic for verification
        let mnemonic = generateMnemonic(padBytes: result.pad)
        phase = .verifying(mnemonic: mnemonic)
    }

    // MARK: - Verification

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

            // Use relay URL from metadata or fallback to settings
            let relayURL = receivedMetadata?.relayURL ?? dependencies.settingsService.relayServerURL

            // Extract disappearing messages setting from metadata
            let disappearingMessages = DisappearingMessages.from(
                seconds: receivedMetadata?.disappearingMessagesSeconds ?? 0
            )

            Log.info(.ceremony, "Receiver finalizing ceremony (disappearing=\(disappearingMessages.displayName))")

            let mnemonic = generateMnemonic(padBytes: padBytes)
            let conversation = try await dependencies.performCeremonyUseCase.finalizeCeremony(
                padBytes: padBytes,
                mnemonic: mnemonic,
                role: .responder,
                relayURL: relayURL,
                customName: finalName,
                disappearingMessages: disappearingMessages
            )

            Log.info(.ceremony, "Ceremony completed: conversation \(conversation.id.prefix(8)), role=responder, pad=\(padBytes.count) bytes")
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
        Log.debug(.ceremony, "Resetting receiver ceremony state")
        phase = .configuringReceiver
        generatedPadBytes = nil
        receivedMetadata = nil
        fountainReceiver = nil
        sourceBlockCount = 0
        receivedFrameCount = 0
        progress = 0.0
    }

    func cancel() {
        Log.info(.ceremony, "Ceremony cancelled")
        phase = .failed(.cancelled)
    }
}
