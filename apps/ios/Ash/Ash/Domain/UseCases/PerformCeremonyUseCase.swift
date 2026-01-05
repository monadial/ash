//
//  PerformCeremonyUseCase.swift
//  Ash
//
//  Domain Layer - Use Case for key exchange ceremony
//  Uses ash-core FFI for cryptographic operations with fountain codes
//
//  Fountain codes enable reliable QR transfer:
//  - Receiver can decode from ANY sufficient subset of blocks
//  - No need to wait for specific frames
//  - Just keep scanning until complete
//

import Foundation
import CryptoKit

/// Notification flag constants for push notification preferences
/// These match the Rust core definitions
enum NotificationFlagsConstants {
    static let notifyNewMessage: UInt16 = 1 << 0
    static let notifyMessageExpiring: UInt16 = 1 << 1
    static let notifyMessageExpired: UInt16 = 1 << 2
    static let notifyDeliveryFailed: UInt16 = 1 << 8
    static let notifyMessageRead: UInt16 = 1 << 9

    /// Default: new message + expiring + delivery failed
    static let defaultFlags: UInt16 = notifyNewMessage | notifyMessageExpiring | notifyDeliveryFailed

    // Color encoding in bits 12-15 (4 bits for up to 16 colors)
    static let colorShift: UInt16 = 12
    static let colorMask: UInt16 = 0xF000  // bits 12-15

    /// Encode color index into notification flags
    static func encodeColor(_ color: ConversationColor, into flags: UInt16) -> UInt16 {
        let colorIndex = UInt16(ConversationColor.allCases.firstIndex(of: color) ?? 0)
        return (flags & ~colorMask) | (colorIndex << colorShift)
    }

    /// Decode color from notification flags
    static func decodeColor(from flags: UInt16) -> ConversationColor {
        let colorIndex = Int((flags & colorMask) >> colorShift)
        let allColors = ConversationColor.allCases
        guard colorIndex < allColors.count else { return .orange }
        return allColors[colorIndex]
    }
}

/// Ceremony metadata that gets transferred via QR
/// Contains TTL, disappearing messages setting, notification preferences, and relay URL
struct CeremonyMetadataSwift: Sendable {
    let ttlSeconds: UInt64
    let disappearingMessagesSeconds: UInt32
    let notificationFlags: UInt16
    let relayURL: String

    init(
        ttlSeconds: UInt64 = MessageTTL.defaultSeconds,
        disappearingMessagesSeconds: UInt32 = 0,
        notificationFlags: UInt16 = NotificationFlagsConstants.defaultFlags,
        relayURL: String
    ) {
        self.ttlSeconds = ttlSeconds
        self.disappearingMessagesSeconds = disappearingMessagesSeconds
        self.notificationFlags = notificationFlags
        self.relayURL = relayURL
    }

    // Helper methods for checking flags
    var notifyNewMessage: Bool { (notificationFlags & NotificationFlagsConstants.notifyNewMessage) != 0 }
    var notifyMessageExpiring: Bool { (notificationFlags & NotificationFlagsConstants.notifyMessageExpiring) != 0 }
    var notifyMessageExpired: Bool { (notificationFlags & NotificationFlagsConstants.notifyMessageExpired) != 0 }
    var notifyDeliveryFailed: Bool { (notificationFlags & NotificationFlagsConstants.notifyDeliveryFailed) != 0 }
}

/// Result of decoding fountain ceremony frames
struct CeremonyResult: Sendable {
    let metadata: CeremonyMetadataSwift
    let padBytes: [UInt8]
    let blocksUsed: UInt32
}

/// Use case for performing the key exchange ceremony
protocol PerformCeremonyUseCaseProtocol: Sendable {
    /// Generate a pad from collected entropy (sender role), returns pad bytes
    func generatePadBytes(entropy: [UInt8], sizeBytes: Int) async throws -> [UInt8]

    /// Create a fountain frame generator for QR display
    /// The generator produces unlimited blocks - display cycles through them
    func createFountainGenerator(
        padBytes: [UInt8],
        metadata: CeremonyMetadataSwift,
        blockSize: UInt32,
        passphrase: String?
    ) async throws -> FountainFrameGenerator

    /// Create a fountain frame receiver for QR scanning
    func createFountainReceiver(passphrase: String?) -> FountainFrameReceiver

    /// Generate mnemonic checksum for verification
    func generateMnemonic(from padBytes: [UInt8]) async -> [String]

    /// Finalize ceremony and create conversation
    /// - Parameters:
    ///   - padBytes: The shared one-time pad bytes
    ///   - mnemonic: The mnemonic checksum for verification
    ///   - role: The role in this conversation (initiator = forward, responder = backward)
    ///   - relayURL: The relay server URL
    ///   - customName: Optional custom name for the conversation
    ///   - disappearingMessages: Display TTL setting for messages (client-side)
    ///   - accentColor: Accent color for the conversation UI
    func finalizeCeremony(
        padBytes: [UInt8],
        mnemonic: [String],
        role: ConversationRole,
        relayURL: String,
        customName: String?,
        disappearingMessages: DisappearingMessages,
        accentColor: ConversationColor
    ) async throws -> Conversation
}

/// Implementation of ceremony use case using ash-core FFI with fountain codes
final class PerformCeremonyUseCase: PerformCeremonyUseCaseProtocol, Sendable {
    private let cryptoService: CryptoServiceProtocol
    private let conversationRepository: ConversationRepository
    private let padManager: PadManagerProtocol
    private let relayServiceFactory: RelayServiceFactory

    init(
        cryptoService: CryptoServiceProtocol,
        conversationRepository: ConversationRepository,
        padManager: PadManagerProtocol,
        relayServiceFactory: @escaping RelayServiceFactory
    ) {
        self.cryptoService = cryptoService
        self.conversationRepository = conversationRepository
        self.padManager = padManager
        self.relayServiceFactory = relayServiceFactory
    }

    /// Hash a token using SHA-256 and return hex-encoded string
    private func hashToken(_ token: String) -> String {
        let data = Data(token.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    func generatePadBytes(entropy: [UInt8], sizeBytes: Int) async throws -> [UInt8] {
        // Determine PadSize from target bytes
        // Sizes: Tiny=32KB, Small=64KB, Medium=256KB, Large=512KB, Huge=1MB
        let padSize: PadSize
        switch sizeBytes {
        case ..<48_000:          // < 48KB → Tiny (32KB)
            padSize = .tiny
        case ..<128_000:         // < 128KB → Small (64KB)
            padSize = .small
        case ..<384_000:         // < 384KB → Medium (256KB)
            padSize = .medium
        case ..<768_000:         // < 768KB → Large (512KB)
            padSize = .large
        default:                 // >= 768KB → Huge (1MB)
            padSize = .huge
        }

        // Generate secure random pad mixed with user entropy
        return try cryptoService.generateSecurePad(userEntropy: entropy, size: padSize)
    }

    func createFountainGenerator(
        padBytes: [UInt8],
        metadata: CeremonyMetadataSwift,
        blockSize: UInt32,
        passphrase: String?
    ) async throws -> FountainFrameGenerator {
        // Create CeremonyMetadata for FFI
        let ffiMetadata = CeremonyMetadata(
            version: 1,
            ttlSeconds: metadata.ttlSeconds,
            disappearingMessagesSeconds: metadata.disappearingMessagesSeconds,
            notificationFlags: metadata.notificationFlags,
            relayUrl: metadata.relayURL
        )

        // Create fountain generator via FFI
        return try Ash.createFountainGenerator(
            metadata: ffiMetadata,
            padBytes: padBytes,
            blockSize: blockSize,
            passphrase: passphrase
        )
    }

    func createFountainReceiver(passphrase: String?) -> FountainFrameReceiver {
        return FountainFrameReceiver(passphrase: passphrase)
    }

    func generateMnemonic(from padBytes: [UInt8]) async -> [String] {
        // Generate 6-word mnemonic from pad bytes via FFI
        return cryptoService.generateMnemonic(from: padBytes, wordCount: 6)
    }

    func finalizeCeremony(
        padBytes: [UInt8],
        mnemonic: [String],
        role: ConversationRole,
        relayURL: String,
        customName: String?,
        disappearingMessages: DisappearingMessages,
        accentColor: ConversationColor
    ) async throws -> Conversation {
        Log.info(.ceremony, "Finalizing ceremony (\(padBytes.count) bytes, disappearing=\(disappearingMessages.displayName), color=\(accentColor.rawValue))")

        // Derive authorization tokens from pad bytes
        let tokens = try Ash.deriveAllTokens(padBytes: padBytes)
        Log.debug(.ceremony, "Authorization tokens derived")

        // Create conversation with disappearing messages setting and accent color
        let conversation = Conversation.fromCeremony(
            padBytes: padBytes,
            mnemonic: mnemonic,
            role: role,
            relayURL: relayURL,
            customName: customName,
            disappearingMessages: disappearingMessages,
            accentColor: accentColor,
            authToken: tokens.authToken,
            burnToken: tokens.burnToken
        )

        Log.debug(.ceremony, "Conversation created")

        // Store pad securely via PadManager
        try await padManager.storePad(bytes: padBytes, for: conversation.id)
        Log.debug(.ceremony, "Pad stored securely")

        // Save conversation
        try await conversationRepository.save(conversation)

        // Register conversation with relay server (fire-and-forget)
        if let relay = relayServiceFactory(relayURL) {
            let authTokenHash = hashToken(tokens.authToken)
            let burnTokenHash = hashToken(tokens.burnToken)
            Task {
                do {
                    try await relay.registerConversation(
                        conversationId: conversation.id,
                        authTokenHash: authTokenHash,
                        burnTokenHash: burnTokenHash
                    )
                    Log.info(.ceremony, "Conversation registered with relay")
                } catch {
                    Log.warning(.ceremony, "Failed to register conversation with relay: \(error)")
                }
            }
        }

        Log.info(.ceremony, "Ceremony complete")
        return conversation
    }
}
