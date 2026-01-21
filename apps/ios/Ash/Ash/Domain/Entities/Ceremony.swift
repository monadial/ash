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

/// Pad size selection for ceremony UI.
/// This is a Swift-side enum for UI purposes, separate from core constraints.
/// Core accepts any size between 32KB and 1GB.
enum PadSizeOption: String, CaseIterable, Identifiable {
    case small = "small"       // 64 KB
    case medium = "medium"     // 256 KB
    case large = "large"       // 512 KB
    case huge = "huge"         // 1 MB
    case custom = "custom"     // User-specified size

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .huge: return "Huge"
        case .custom: return "Custom"
        }
    }

    /// Preset size in bytes (nil for custom)
    var presetBytes: UInt64? {
        switch self {
        case .small: return 64 * 1024      // 64 KB
        case .medium: return 256 * 1024    // 256 KB
        case .large: return 512 * 1024     // 512 KB
        case .huge: return 1024 * 1024     // 1 MB
        case .custom: return nil
        }
    }

    /// Human-readable size description
    var sizeDescription: String {
        switch self {
        case .small: return "64 KB"
        case .medium: return "256 KB"
        case .large: return "512 KB"
        case .huge: return "1 MB"
        case .custom: return "Custom"
        }
    }

    /// User-friendly description
    var description: String {
        guard let bytes = presetBytes else {
            return "Choose your own size"
        }
        return "~\(estimatedMessages(for: bytes)) messages, ~\(approximateFrames(for: bytes)) QR frames"
    }

    /// Approximate QR frames needed for transfer
    func approximateFrames(for bytes: UInt64) -> Int {
        // Extended frame format: 6 bytes header + 4 bytes CRC = 10 bytes overhead
        // Max payload 900 bytes → effective payload ~890 bytes
        // +1 for metadata frame (frame 0)
        let effectivePayload: UInt64 = 890
        return Int((bytes + effectivePayload - 1) / effectivePayload) + 1
    }

    /// Estimated number of messages this pad can support.
    /// Formula: usable_bytes / (auth_overhead + avg_message_size)
    /// where auth_overhead = 64 bytes (Wegman-Carter MAC)
    /// and avg_message_size = 100 bytes (typical short message)
    func estimatedMessages(for bytes: UInt64) -> Int {
        let reservedForTokens: UInt64 = 160  // First 160 bytes for token derivation
        let authOverhead: UInt64 = 64        // MAC overhead per message
        let avgMessageSize: UInt64 = 100     // Typical message size
        let bytesPerMessage = authOverhead + avgMessageSize
        let usableBytes = bytes > reservedForTokens ? bytes - reservedForTokens : 0
        return Int(usableBytes / bytesPerMessage)
    }

    /// Estimated messages for preset sizes
    var estimatedMessages: Int {
        guard let bytes = presetBytes else { return 0 }
        return estimatedMessages(for: bytes)
    }

    /// Approximate QR frames for preset sizes
    var approximateFrames: Int {
        guard let bytes = presetBytes else { return 0 }
        return approximateFrames(for: bytes)
    }
}

/// Pad size limits from core
enum PadSizeLimits {
    /// Minimum pad size (32 KB)
    static let minimumBytes: UInt64 = 32 * 1024
    /// Maximum pad size (10 MB for UI, core supports up to 1 GB)
    static let maximumBytes: UInt64 = 10 * 1024 * 1024

    /// Format bytes as human-readable string
    static func formatBytes(_ bytes: UInt64) -> String {
        if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        } else if bytes >= 1024 {
            return String(format: "%.0f KB", Double(bytes) / 1024.0)
        } else {
            return "\(bytes) bytes"
        }
    }

    /// Validate pad size
    static func isValid(_ bytes: UInt64) -> Bool {
        bytes >= minimumBytes && bytes <= maximumBytes
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
    var selectedPadSizeOption: PadSizeOption = .medium
    var customPadSizeBytes: UInt64 = 256 * 1024  // Default custom size
    var entropyProgress: Double = 0.0
    var collectedEntropy: [UInt8] = []
    var generatedPad: [UInt8]? = nil
    var scannedFrames: Set<Int> = []
    var totalFrames: Int = 0

    /// Required passphrase for QR frame encryption (spoken between parties)
    var passphrase: String = ""

    /// Get the actual pad size in bytes
    var padSizeBytes: UInt64 {
        selectedPadSizeOption.presetBytes ?? customPadSizeBytes
    }

    /// Optional custom name for the conversation
    var conversationName: String? = nil

    /// Disappearing messages setting (client-side display TTL)
    var disappearingMessages: DisappearingMessages = .off

    /// Whether message padding is enabled (hides message length)
    var messagePaddingEnabled: Bool = false

    /// Minimum message size when padding is enabled
    var messagePaddingSize: MessagePaddingSize = .bytes32

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
