//
//  CeremonyTests.swift
//  AshTests
//
//  Unit tests for Ceremony domain entities
//

import Testing
import Foundation
@testable import Ash

// MARK: - CeremonyRole Tests

struct CeremonyRoleTests {

    @Test func rawValues_areCorrect() {
        #expect(CeremonyRole.sender.rawValue == "sender")
        #expect(CeremonyRole.receiver.rawValue == "receiver")
    }
}

// MARK: - CeremonyError Tests

struct CeremonyErrorTests {

    @Test func localizedDescription_insufficientEntropy() {
        let error = CeremonyError.insufficientEntropy
        #expect(error.localizedDescription.contains("randomness"))
    }

    @Test func localizedDescription_qrGenerationFailed() {
        let error = CeremonyError.qrGenerationFailed
        #expect(error.localizedDescription.contains("QR"))
    }

    @Test func localizedDescription_qrScanFailed() {
        let error = CeremonyError.qrScanFailed
        #expect(error.localizedDescription.contains("scan"))
    }

    @Test func localizedDescription_frameDecodingFailed() {
        let error = CeremonyError.frameDecodingFailed
        #expect(error.localizedDescription.contains("Invalid"))
    }

    @Test func localizedDescription_checksumMismatch() {
        let error = CeremonyError.checksumMismatch
        #expect(error.localizedDescription.contains("Checksum"))
    }

    @Test func localizedDescription_padReconstructionFailed() {
        let error = CeremonyError.padReconstructionFailed
        #expect(error.localizedDescription.contains("reconstruct"))
    }

    @Test func localizedDescription_cancelled() {
        let error = CeremonyError.cancelled
        #expect(error.localizedDescription.contains("cancelled"))
    }

    @Test func equatable_sameErrors_areEqual() {
        #expect(CeremonyError.cancelled == CeremonyError.cancelled)
        #expect(CeremonyError.qrScanFailed == CeremonyError.qrScanFailed)
    }
}

// MARK: - CeremonyPhase Tests

struct CeremonyPhaseTests {

    @Test func equatable_idle() {
        #expect(CeremonyPhase.idle == CeremonyPhase.idle)
    }

    @Test func equatable_selectingRole() {
        #expect(CeremonyPhase.selectingRole == CeremonyPhase.selectingRole)
    }

    @Test func equatable_selectingPadSize() {
        #expect(CeremonyPhase.selectingPadSize == CeremonyPhase.selectingPadSize)
    }

    @Test func equatable_collectingEntropy() {
        #expect(CeremonyPhase.collectingEntropy == CeremonyPhase.collectingEntropy)
    }

    @Test func equatable_generatingPad() {
        #expect(CeremonyPhase.generatingPad == CeremonyPhase.generatingPad)
    }

    @Test func equatable_generatingQRCodes_sameValues() {
        let phase1 = CeremonyPhase.generatingQRCodes(progress: 0.5, total: 10)
        let phase2 = CeremonyPhase.generatingQRCodes(progress: 0.5, total: 10)
        #expect(phase1 == phase2)
    }

    @Test func equatable_generatingQRCodes_differentValues() {
        let phase1 = CeremonyPhase.generatingQRCodes(progress: 0.5, total: 10)
        let phase2 = CeremonyPhase.generatingQRCodes(progress: 0.8, total: 10)
        #expect(phase1 != phase2)
    }

    @Test func equatable_transferring_sameValues() {
        let phase1 = CeremonyPhase.transferring(currentFrame: 5, totalFrames: 10)
        let phase2 = CeremonyPhase.transferring(currentFrame: 5, totalFrames: 10)
        #expect(phase1 == phase2)
    }

    @Test func equatable_transferring_differentValues() {
        let phase1 = CeremonyPhase.transferring(currentFrame: 5, totalFrames: 10)
        let phase2 = CeremonyPhase.transferring(currentFrame: 6, totalFrames: 10)
        #expect(phase1 != phase2)
    }

    @Test func equatable_verifying_sameMnemonic() {
        let phase1 = CeremonyPhase.verifying(mnemonic: ["a", "b", "c"])
        let phase2 = CeremonyPhase.verifying(mnemonic: ["a", "b", "c"])
        #expect(phase1 == phase2)
    }

    @Test func equatable_failed_sameError() {
        let phase1 = CeremonyPhase.failed(.cancelled)
        let phase2 = CeremonyPhase.failed(.cancelled)
        #expect(phase1 == phase2)
    }

    @Test func equatable_failed_differentError() {
        let phase1 = CeremonyPhase.failed(.cancelled)
        let phase2 = CeremonyPhase.failed(.qrScanFailed)
        #expect(phase1 != phase2)
    }
}

// MARK: - CeremonyState Tests

struct CeremonyStateTests {

    @Test func init_hasDefaultValues() {
        let state = CeremonyState()

        #expect(state.phase == .idle)
        #expect(state.role == .sender)
        #expect(state.selectedPadSize == .medium)
        #expect(state.entropyProgress == 0.0)
        #expect(state.collectedEntropy.isEmpty)
        #expect(state.generatedPad == nil)
        #expect(state.scannedFrames.isEmpty)
        #expect(state.totalFrames == 0)
    }

    @Test func isInProgress_idle_returnsFalse() {
        var state = CeremonyState()
        state.phase = .idle

        #expect(state.isInProgress == false)
    }

    @Test func isInProgress_completed_returnsFalse() {
        var state = CeremonyState()
        let padBytes = [UInt8](repeating: 0xAB, count: 1000)
        let conversation = Conversation.fromCeremony(
            padBytes: padBytes,
            mnemonic: ["a", "b", "c", "d", "e", "f"],
            role: .initiator,
            relayURL: "https://relay.test",
            authToken: "test-auth-token-0123456789abcdef0123456789abcdef0123456789abcdef01234567",
            burnToken: "test-burn-token-0123456789abcdef0123456789abcdef0123456789abcdef01234567"
        )
        state.phase = .completed(conversation: conversation)

        #expect(state.isInProgress == false)
    }

    @Test func isInProgress_failed_returnsFalse() {
        var state = CeremonyState()
        state.phase = .failed(.cancelled)

        #expect(state.isInProgress == false)
    }

    @Test func isInProgress_selectingRole_returnsTrue() {
        var state = CeremonyState()
        state.phase = .selectingRole

        #expect(state.isInProgress == true)
    }

    @Test func isInProgress_collectingEntropy_returnsTrue() {
        var state = CeremonyState()
        state.phase = .collectingEntropy

        #expect(state.isInProgress == true)
    }

    @Test func isInProgress_transferring_returnsTrue() {
        var state = CeremonyState()
        state.phase = .transferring(currentFrame: 1, totalFrames: 10)

        #expect(state.isInProgress == true)
    }

    @Test func canCancel_idle_returnsFalse() {
        var state = CeremonyState()
        state.phase = .idle

        #expect(state.canCancel == false)
    }

    @Test func canCancel_completed_returnsFalse() {
        var state = CeremonyState()
        let padBytes = [UInt8](repeating: 0xAB, count: 1000)
        let conversation = Conversation.fromCeremony(
            padBytes: padBytes,
            mnemonic: ["a", "b", "c", "d", "e", "f"],
            role: .initiator,
            relayURL: "https://relay.test",
            authToken: "test-auth-token-0123456789abcdef0123456789abcdef0123456789abcdef01234567",
            burnToken: "test-burn-token-0123456789abcdef0123456789abcdef0123456789abcdef01234567"
        )
        state.phase = .completed(conversation: conversation)

        #expect(state.canCancel == false)
    }

    @Test func canCancel_inProgress_returnsTrue() {
        var state = CeremonyState()
        state.phase = .collectingEntropy

        #expect(state.canCancel == true)
    }

    @Test func canCancel_failed_returnsTrue() {
        var state = CeremonyState()
        state.phase = .failed(.cancelled)

        #expect(state.canCancel == true)
    }

    @Test func reset_restoresDefaultState() {
        var state = CeremonyState()
        state.phase = .collectingEntropy
        state.role = .receiver
        state.entropyProgress = 0.75
        state.collectedEntropy = [1, 2, 3]
        state.totalFrames = 50

        state.reset()

        #expect(state.phase == .idle)
        #expect(state.role == .sender)
        #expect(state.entropyProgress == 0.0)
        #expect(state.collectedEntropy.isEmpty)
        #expect(state.totalFrames == 0)
    }
}

// MARK: - PadSize Extension Tests

struct PadSizeExtensionTests {

    @Test func allCases_containsFiveSizes() {
        #expect(PadSize.allCases.count == 5)
        #expect(PadSize.allCases.contains(.tiny))
        #expect(PadSize.allCases.contains(.small))
        #expect(PadSize.allCases.contains(.medium))
        #expect(PadSize.allCases.contains(.large))
        #expect(PadSize.allCases.contains(.huge))
    }

    @Test func displayName_allSizes() {
        #expect(PadSize.tiny.displayName == "Tiny")
        #expect(PadSize.small.displayName == "Small")
        #expect(PadSize.medium.displayName == "Medium")
        #expect(PadSize.large.displayName == "Large")
        #expect(PadSize.huge.displayName == "Huge")
    }

    @Test func bytes_allSizes() {
        #expect(PadSize.tiny.bytes == 32 * 1024)    // 32 KB
        #expect(PadSize.small.bytes == 64 * 1024)   // 64 KB
        #expect(PadSize.medium.bytes == 256 * 1024) // 256 KB
        #expect(PadSize.large.bytes == 512 * 1024)  // 512 KB
        #expect(PadSize.huge.bytes == 1024 * 1024)  // 1 MB
    }

    @Test func description_containsMessages() {
        #expect(PadSize.tiny.description.contains("messages"))
        #expect(PadSize.small.description.contains("messages"))
        #expect(PadSize.medium.description.contains("messages"))
        #expect(PadSize.large.description.contains("messages"))
        #expect(PadSize.huge.description.contains("messages"))
    }

    @Test func description_containsFrames() {
        #expect(PadSize.tiny.description.contains("frames"))
        #expect(PadSize.small.description.contains("frames"))
        #expect(PadSize.medium.description.contains("frames"))
        #expect(PadSize.large.description.contains("frames"))
        #expect(PadSize.huge.description.contains("frames"))
    }

    @Test func approximateFrames_calculatesCorrectly() {
        // ~890 bytes effective payload per frame + 1 for metadata frame
        // Tiny: 32KB / 890 + 1 = 37 + 1 = 38
        // Small: 64KB / 890 + 1 = 74 + 1 = 75
        // Medium: 256KB / 890 + 1 = 295 + 1 = 296
        // Large: 512KB / 890 + 1 = 589 + 1 = 590
        // Huge: 1MB / 890 + 1 = 1179 + 1 = 1180
        #expect(PadSize.tiny.approximateFrames == 38)
        #expect(PadSize.small.approximateFrames == 75)
        #expect(PadSize.medium.approximateFrames == 296)
        #expect(PadSize.large.approximateFrames == 590)
        #expect(PadSize.huge.approximateFrames == 1180)
    }

    @Test func id_usesDisplayName() {
        #expect(PadSize.tiny.id == "Tiny")
        #expect(PadSize.small.id == "Small")
        #expect(PadSize.medium.id == "Medium")
        #expect(PadSize.large.id == "Large")
        #expect(PadSize.huge.id == "Huge")
    }
}

// MARK: - Ceremony Frame Count Tests (FFI Integration)

struct CeremonyFrameCountTests {
    /// Max payload per QR frame (same as CeremonyViewModel)
    private let maxPayloadPerFrame: UInt32 = 900

    @Test func frameCount_smallPad_matchesEstimate() throws {
        // Generate a small pad worth of random bytes
        let padBytes = [UInt8](repeating: 0xAB, count: Int(PadSize.small.bytes))

        // Create ceremony metadata
        let metadata = CeremonyMetadata(
            version: 1,
            ttlSeconds: 172800, // 48 hours
            disappearingMessagesSeconds: 0,
            notificationFlags: 0x0103, // default flags
            relayUrl: "https://relay.ash.test"
        )

        // Create ceremony frames (frame 0 = metadata, frames 1-N = pad data)
        let frames = try createCeremonyFrames(
            metadata: metadata,
            padBytes: padBytes,
            maxPayload: maxPayloadPerFrame,
            passphrase: nil
        )

        let actualCount = frames.count
        let estimatedCount = PadSize.small.approximateFrames

        // Should be within 5% or 2 frames of estimate
        let tolerance = max(2, estimatedCount / 20)
        #expect(abs(actualCount - estimatedCount) <= tolerance,
                "Small: \(actualCount) actual vs \(estimatedCount) estimated (tolerance: \(tolerance))")
    }

    @Test func frameCount_mediumPad_matchesEstimate() throws {
        let padBytes = [UInt8](repeating: 0xCD, count: Int(PadSize.medium.bytes))

        let metadata = CeremonyMetadata(
            version: 1,
            ttlSeconds: 172800,
            disappearingMessagesSeconds: 0,
            notificationFlags: 0x0103,
            relayUrl: "https://relay.ash.test"
        )

        let frames = try createCeremonyFrames(
            metadata: metadata,
            padBytes: padBytes,
            maxPayload: maxPayloadPerFrame,
            passphrase: nil
        )

        let actualCount = frames.count
        let estimatedCount = PadSize.medium.approximateFrames

        let tolerance = max(2, estimatedCount / 20)
        #expect(abs(actualCount - estimatedCount) <= tolerance,
                "Medium: \(actualCount) actual vs \(estimatedCount) estimated (tolerance: \(tolerance))")
    }

    @Test func frameCount_largePad_matchesEstimate() throws {
        let padBytes = [UInt8](repeating: 0xEF, count: Int(PadSize.large.bytes))

        let metadata = CeremonyMetadata(
            version: 1,
            ttlSeconds: 172800,
            disappearingMessagesSeconds: 0,
            notificationFlags: 0x0103,
            relayUrl: "https://relay.ash.test"
        )

        let frames = try createCeremonyFrames(
            metadata: metadata,
            padBytes: padBytes,
            maxPayload: maxPayloadPerFrame,
            passphrase: nil
        )

        let actualCount = frames.count
        let estimatedCount = PadSize.large.approximateFrames

        let tolerance = max(2, estimatedCount / 20)
        #expect(abs(actualCount - estimatedCount) <= tolerance,
                "Large: \(actualCount) actual vs \(estimatedCount) estimated (tolerance: \(tolerance))")
    }

    @Test func frameCount_tinyPad_matchesEstimate() throws {
        let padBytes = [UInt8](repeating: 0x11, count: Int(PadSize.tiny.bytes))

        let metadata = CeremonyMetadata(
            version: 1,
            ttlSeconds: 172800,
            disappearingMessagesSeconds: 0,
            notificationFlags: 0x0103,
            relayUrl: "https://relay.ash.test"
        )

        let frames = try createCeremonyFrames(
            metadata: metadata,
            padBytes: padBytes,
            maxPayload: maxPayloadPerFrame,
            passphrase: nil
        )

        let actualCount = frames.count
        let estimatedCount = PadSize.tiny.approximateFrames

        let tolerance = max(2, estimatedCount / 20)
        #expect(abs(actualCount - estimatedCount) <= tolerance,
                "Tiny: \(actualCount) actual vs \(estimatedCount) estimated (tolerance: \(tolerance))")
    }

    @Test func frameCount_hugePad_matchesEstimate() throws {
        let padBytes = [UInt8](repeating: 0xFF, count: Int(PadSize.huge.bytes))

        let metadata = CeremonyMetadata(
            version: 1,
            ttlSeconds: 172800,
            disappearingMessagesSeconds: 0,
            notificationFlags: 0x0103,
            relayUrl: "https://relay.ash.test"
        )

        let frames = try createCeremonyFrames(
            metadata: metadata,
            padBytes: padBytes,
            maxPayload: maxPayloadPerFrame,
            passphrase: nil
        )

        let actualCount = frames.count
        let estimatedCount = PadSize.huge.approximateFrames

        let tolerance = max(2, estimatedCount / 20)
        #expect(abs(actualCount - estimatedCount) <= tolerance,
                "Huge: \(actualCount) actual vs \(estimatedCount) estimated (tolerance: \(tolerance))")
    }

    @Test func frameCount_withPassphrase_sameAsWithout() throws {
        // Passphrase encryption shouldn't change frame count significantly
        let padBytes = [UInt8](repeating: 0x42, count: Int(PadSize.small.bytes))

        let metadata = CeremonyMetadata(
            version: 1,
            ttlSeconds: 604800, // 7 days
            disappearingMessagesSeconds: 0,
            notificationFlags: 0x0103,
            relayUrl: "https://relay.ash.test"
        )

        let framesWithout = try createCeremonyFrames(
            metadata: metadata,
            padBytes: padBytes,
            maxPayload: maxPayloadPerFrame,
            passphrase: nil
        )

        let framesWith = try createCeremonyFrames(
            metadata: metadata,
            padBytes: padBytes,
            maxPayload: maxPayloadPerFrame,
            passphrase: "test-passphrase"
        )

        print("Without passphrase: \(framesWithout.count) frames")
        print("With passphrase: \(framesWith.count) frames")

        // Should be the same or very close (encryption adds minimal overhead)
        #expect(abs(framesWithout.count - framesWith.count) <= 1)
    }

    @Test func frameCount_metadataFrameIsFirst() throws {
        let padBytes = [UInt8](repeating: 0x00, count: 10000)

        let metadata = CeremonyMetadata(
            version: 1,
            ttlSeconds: 3600,
            disappearingMessagesSeconds: 0,
            notificationFlags: 0x0103,
            relayUrl: "https://test.relay"
        )

        let frames = try createCeremonyFrames(
            metadata: metadata,
            padBytes: padBytes,
            maxPayload: maxPayloadPerFrame,
            passphrase: nil
        )

        #expect(frames.count > 1, "Should have at least metadata frame + 1 data frame")

        // Decode the first frame and verify it has metadata flag
        let firstFrame = frames[0]
        // Extended frame format: [magic 0xA5][flags][index][total][payload][crc]
        #expect(firstFrame[0] == 0xA5, "First byte should be extended magic")

        let flags = firstFrame[1]
        let metadataFlag: UInt8 = 0b0000_0010
        #expect((flags & metadataFlag) != 0, "Frame 0 should have metadata flag set")
    }

    @Test func frameCount_roundtrip_preservesData() throws {
        let originalPad = [UInt8]((0..<1000).map { UInt8($0 % 256) })

        let metadata = CeremonyMetadata(
            version: 1,
            ttlSeconds: 86400,
            disappearingMessagesSeconds: 0,
            notificationFlags: 0x0103,
            relayUrl: "https://roundtrip.test"
        )

        // Encode
        let frames = try createCeremonyFrames(
            metadata: metadata,
            padBytes: originalPad,
            maxPayload: maxPayloadPerFrame,
            passphrase: nil
        )

        // Decode
        let result = try decodeCeremonyFrames(
            encodedFrames: frames,
            passphrase: nil
        )

        // Verify metadata
        #expect(result.metadata.ttlSeconds == 86400)
        #expect(result.metadata.disappearingMessagesSeconds == 0)
        #expect(result.metadata.relayUrl == "https://roundtrip.test")

        // Verify pad data
        #expect(result.pad == originalPad, "Pad data should match after roundtrip")

        print("Roundtrip: \(originalPad.count) bytes -> \(frames.count) frames -> \(result.pad.count) bytes")
    }
}
