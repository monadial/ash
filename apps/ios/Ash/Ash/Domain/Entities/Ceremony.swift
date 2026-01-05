//
//  Ceremony.swift
//  Ash
//
//  Domain Entity - Key exchange ceremony state
//

import Foundation

/// Role in the ceremony - who generates vs receives the pad
enum CeremonyRole: String, Sendable {
    case sender    // Generates pad, displays QR codes
    case receiver  // Scans QR codes from sender
}

/// Extension to add UI-friendly properties to the FFI PadSize enum
extension PadSize: CaseIterable, Identifiable {
    public static var allCases: [PadSize] { [.tiny, .small, .medium, .large, .huge] }

    public var id: String { displayName }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .huge: return "Huge"
        }
    }

    var bytes: UInt64 {
        switch self {
        case .tiny: return 32 * 1024       // 32 KB
        case .small: return 64 * 1024      // 64 KB
        case .medium: return 256 * 1024    // 256 KB
        case .large: return 512 * 1024     // 512 KB
        case .huge: return 1024 * 1024     // 1 MB
        }
    }

    /// User-friendly description
    var description: String {
        "~\(estimatedMessages) messages, ~\(approximateFrames) QR frames"
    }

    /// Approximate QR frames needed for transfer
    var approximateFrames: Int {
        // Extended frame format: 6 bytes header + 4 bytes CRC = 10 bytes overhead
        // Max payload 900 bytes → effective payload ~890 bytes
        // +1 for metadata frame (frame 0)
        let effectivePayload = 890
        return Int((bytes + UInt64(effectivePayload) - 1) / UInt64(effectivePayload)) + 1
    }

    /// Estimated number of messages this pad can support
    var estimatedMessages: Int {
        switch self {
        case .tiny: return 50
        case .small: return 100
        case .medium: return 500
        case .large: return 1000
        case .huge: return 2000
        }
    }
}

/// Current phase of the ceremony
enum CeremonyPhase: Equatable, Sendable {
    case idle
    case selectingRole
    case selectingPadSize
    case configuringOptions          // Sender: passphrase + name options
    case confirmingConsent           // Sender: ethics/consent confirmation
    case collectingEntropy
    case generatingPad
    case generatingQRCodes(progress: Double, total: Int)
    case configuringReceiver        // Receiver: passphrase config before scanning
    case transferring(currentFrame: Int, totalFrames: Int)
    case verifying(mnemonic: [String])
    case completed(conversation: Conversation)
    case failed(CeremonyError)
}

/// Errors that can occur during ceremony
enum CeremonyError: Error, Equatable, Sendable {
    case insufficientEntropy
    case qrGenerationFailed
    case qrScanFailed
    case frameDecodingFailed
    case checksumMismatch
    case padReconstructionFailed
    case cancelled

    var localizedDescription: String {
        switch self {
        case .insufficientEntropy:
            return "Not enough randomness collected. Please try again."
        case .qrGenerationFailed:
            return "Failed to generate QR codes."
        case .qrScanFailed:
            return "Failed to scan QR code. Please try again."
        case .frameDecodingFailed:
            return "Invalid QR code data."
        case .checksumMismatch:
            return "Checksum mismatch - ceremony aborted for security."
        case .padReconstructionFailed:
            return "Failed to reconstruct pad from frames."
        case .cancelled:
            return "Ceremony was cancelled."
        }
    }
}

/// Consent checkboxes that must be confirmed before proceeding
struct ConsentState: Equatable {
    var environmentConfirmed: Bool = false    // No one watching
    var notUnderSurveillance: Bool = false    // Not coerced
    var ethicsUnderstood: Bool = false        // Understands ethical use
    var keyLossUnderstood: Bool = false       // Understands no recovery
    var relayWarningUnderstood: Bool = false  // Understands relay limitations
    var dataLossUnderstood: Bool = false      // Understands relay data is ephemeral
    var burnUnderstood: Bool = false          // Understands burn destroys keys

    var allConfirmed: Bool {
        environmentConfirmed &&
        notUnderSurveillance &&
        ethicsUnderstood &&
        keyLossUnderstood &&
        relayWarningUnderstood &&
        dataLossUnderstood &&
        burnUnderstood
    }
}

/// Immutable snapshot of ceremony progress (simplified ephemeral design)
struct CeremonyState: Equatable {
    var phase: CeremonyPhase = .idle
    var role: CeremonyRole = .sender
    var selectedPadSize: PadSize = .medium
    var entropyProgress: Double = 0.0
    var collectedEntropy: [UInt8] = []
    var generatedPad: [UInt8]? = nil
    var scannedFrames: Set<Int> = []
    var totalFrames: Int = 0

    /// Optional passphrase for QR frame encryption (spoken between parties)
    var passphrase: String? = nil

    /// Whether passphrase encryption is enabled
    var isPassphraseEnabled: Bool = false

    /// Optional custom name for the conversation
    var conversationName: String? = nil

    /// Disappearing messages setting (client-side display TTL)
    var disappearingMessages: DisappearingMessages = .off

    /// Consent checkboxes state
    var consent: ConsentState = ConsentState()

    var isInProgress: Bool {
        switch phase {
        case .idle, .completed, .failed:
            return false
        default:
            return true
        }
    }

    var canCancel: Bool {
        switch phase {
        case .idle, .completed:
            return false
        default:
            return true
        }
    }

    /// Reset to initial state
    mutating func reset() {
        self = CeremonyState()
    }
}
