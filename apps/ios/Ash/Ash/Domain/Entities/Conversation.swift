//
//  Conversation.swift
//  Ash
//
//  Domain Entity - Pure business model
//
//  Simplified ephemeral design:
//  - Messages stored in server RAM only
//  - Deleted on client ACK or TTL expiry
//  - No persistence, no complex modes
//

import Foundation
import CryptoKit

/// Role in the conversation - determines pad consumption direction
/// This ensures both parties never use the same pad bytes
enum ConversationRole: String, Codable, Sendable {
    /// Initiator (ceremony sender): consumes pad forward from byte 0
    case initiator
    /// Responder (ceremony receiver): consumes pad backward from last byte
    case responder
}

/// Server TTL - How long unread messages wait on server before expiring
/// Messages are stored in server RAM only. Server restart = all unread messages lost.
enum MessageRetention: String, Codable, CaseIterable, Sendable {
    case fiveMinutes
    case oneHour
    case twelveHours
    case oneDay
    case sevenDays

    var seconds: UInt64 {
        switch self {
        case .fiveMinutes: return 300
        case .oneHour: return 3600
        case .twelveHours: return 43200
        case .oneDay: return 86400
        case .sevenDays: return 604800
        }
    }

    var displayName: String {
        switch self {
        case .fiveMinutes: return "5 minutes"
        case .oneHour: return "1 hour"
        case .twelveHours: return "12 hours"
        case .oneDay: return "1 day"
        case .sevenDays: return "7 days"
        }
    }

    var shortName: String {
        switch self {
        case .fiveMinutes: return "5m"
        case .oneHour: return "1h"
        case .twelveHours: return "12h"
        case .oneDay: return "1d"
        case .sevenDays: return "7d"
        }
    }

    /// Create from seconds value (received from ceremony metadata)
    static func from(seconds: UInt64) -> MessageRetention {
        switch seconds {
        case 0...600: return .fiveMinutes
        case 601...7200: return .oneHour
        case 7201...64800: return .twelveHours
        case 64801...172800: return .oneDay
        default: return .sevenDays
        }
    }
}

/// Legacy constant for backward compatibility
enum MessageTTL {
    static let defaultSeconds: UInt64 = 300
    static var displayName: String { "5 minutes" }
}

/// Display TTL - How long messages remain visible on screen after viewing
/// Similar to Signal's disappearing messages feature.
/// This is purely client-side; messages disappear from UI after the timer expires.
enum DisappearingMessages: String, Codable, CaseIterable, Sendable {
    case off
    case thirtySeconds
    case fiveMinutes
    case tenMinutes
    case thirtyMinutes
    case oneHour

    var seconds: TimeInterval? {
        switch self {
        case .off: return nil
        case .thirtySeconds: return 30
        case .fiveMinutes: return 300
        case .tenMinutes: return 600
        case .thirtyMinutes: return 1800
        case .oneHour: return 3600
        }
    }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .thirtySeconds: return "30 seconds"
        case .fiveMinutes: return "5 minutes"
        case .tenMinutes: return "10 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        }
    }

    var isEnabled: Bool {
        self != .off
    }

    /// Create from seconds value (received from ceremony metadata)
    static func from(seconds: UInt32) -> DisappearingMessages {
        switch seconds {
        case 0: return .off
        case 1...45: return .thirtySeconds
        case 46...450: return .fiveMinutes
        case 451...900: return .tenMinutes
        case 901...2700: return .thirtyMinutes
        default: return .oneHour
        }
    }
}

/// Represents a secure conversation with another party
/// Simplified ephemeral model - immediate burn only, fixed TTL
struct Conversation: Identifiable, Equatable, Hashable, Sendable, Codable {
    /// Conversation ID derived from shared pad bytes (base64-encoded hash)
    /// Both parties derive the same ID from their identical pads
    let id: String
    let createdAt: Date
    var lastActivity: Date
    var remainingBytes: UInt64
    let totalBytes: UInt64
    var unreadCount: Int
    let mnemonicChecksum: [String]
    var customName: String?

    /// Role determines pad consumption direction
    /// - Initiator: consumes forward (0 → middle)
    /// - Responder: consumes backward (end → middle)
    let role: ConversationRole

    /// Bytes consumed by this device for sending
    var sendOffset: UInt64

    /// Bytes consumed by the peer (learned from received message sequences)
    var peerConsumed: UInt64

    // MARK: - Relay Configuration

    /// The relay server URL for this conversation
    var relayURL: String

    // MARK: - Display Settings

    /// How long messages remain visible on screen after viewing (client-side only)
    var disappearingMessages: DisappearingMessages

    /// Custom accent color for this conversation
    var accentColor: ConversationColor

    // MARK: - Relay State

    /// Last known cursor position for polling messages
    var relayCursor: String?

    /// Monotonically increasing sequence for stable ordering
    var activitySequence: UInt64

    /// Whether this conversation has been burned by peer
    var peerBurnedAt: Date?

    /// Sequences of incoming messages we've already processed (for deduplication)
    var processedIncomingSequences: Set<UInt64>

    // MARK: - Authorization Tokens (derived from pad during ceremony)

    /// Auth token for API operations (hex-encoded, 64 chars)
    let authToken: String

    /// Burn token for burn operations (hex-encoded, 64 chars)
    let burnToken: String

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, createdAt, lastActivity, remainingBytes, totalBytes
        case unreadCount, mnemonicChecksum, customName, sendOffset, peerConsumed
        case relayURL, disappearingMessages, accentColor, role, relayCursor, activitySequence
        case processedIncomingSequences, peerBurnedAt
        case authToken, burnToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastActivity = try container.decode(Date.self, forKey: .lastActivity)
        remainingBytes = try container.decode(UInt64.self, forKey: .remainingBytes)
        totalBytes = try container.decode(UInt64.self, forKey: .totalBytes)
        unreadCount = try container.decode(Int.self, forKey: .unreadCount)
        mnemonicChecksum = try container.decode([String].self, forKey: .mnemonicChecksum)
        customName = try container.decodeIfPresent(String.self, forKey: .customName)
        role = try container.decodeIfPresent(ConversationRole.self, forKey: .role) ?? .initiator
        sendOffset = try container.decodeIfPresent(UInt64.self, forKey: .sendOffset) ?? 0
        peerConsumed = try container.decodeIfPresent(UInt64.self, forKey: .peerConsumed) ?? 0
        relayURL = try container.decode(String.self, forKey: .relayURL)
        disappearingMessages = try container.decodeIfPresent(DisappearingMessages.self, forKey: .disappearingMessages) ?? .off
        accentColor = try container.decodeIfPresent(ConversationColor.self, forKey: .accentColor) ?? .indigo
        relayCursor = try container.decodeIfPresent(String.self, forKey: .relayCursor)
        activitySequence = try container.decodeIfPresent(UInt64.self, forKey: .activitySequence) ?? 0
        peerBurnedAt = try container.decodeIfPresent(Date.self, forKey: .peerBurnedAt)
        processedIncomingSequences = try container.decodeIfPresent(Set<UInt64>.self, forKey: .processedIncomingSequences) ?? []
        authToken = try container.decodeIfPresent(String.self, forKey: .authToken) ?? ""
        burnToken = try container.decodeIfPresent(String.self, forKey: .burnToken) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastActivity, forKey: .lastActivity)
        try container.encode(remainingBytes, forKey: .remainingBytes)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(unreadCount, forKey: .unreadCount)
        try container.encode(mnemonicChecksum, forKey: .mnemonicChecksum)
        try container.encodeIfPresent(customName, forKey: .customName)
        try container.encode(role, forKey: .role)
        try container.encode(sendOffset, forKey: .sendOffset)
        try container.encode(peerConsumed, forKey: .peerConsumed)
        try container.encode(relayURL, forKey: .relayURL)
        try container.encode(disappearingMessages, forKey: .disappearingMessages)
        try container.encode(accentColor, forKey: .accentColor)
        try container.encodeIfPresent(relayCursor, forKey: .relayCursor)
        try container.encode(activitySequence, forKey: .activitySequence)
        try container.encodeIfPresent(peerBurnedAt, forKey: .peerBurnedAt)
        try container.encode(processedIncomingSequences, forKey: .processedIncomingSequences)
        try container.encode(authToken, forKey: .authToken)
        try container.encode(burnToken, forKey: .burnToken)
    }

    init(
        id: String,
        createdAt: Date,
        lastActivity: Date,
        remainingBytes: UInt64,
        totalBytes: UInt64,
        unreadCount: Int,
        mnemonicChecksum: [String],
        customName: String?,
        role: ConversationRole,
        sendOffset: UInt64,
        peerConsumed: UInt64,
        relayURL: String,
        disappearingMessages: DisappearingMessages = .off,
        accentColor: ConversationColor = .indigo,
        relayCursor: String? = nil,
        activitySequence: UInt64 = 0,
        peerBurnedAt: Date? = nil,
        processedIncomingSequences: Set<UInt64> = [],
        authToken: String,
        burnToken: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastActivity = lastActivity
        self.remainingBytes = remainingBytes
        self.totalBytes = totalBytes
        self.unreadCount = unreadCount
        self.mnemonicChecksum = mnemonicChecksum
        self.customName = customName
        self.role = role
        self.sendOffset = sendOffset
        self.peerConsumed = peerConsumed
        self.relayURL = relayURL
        self.disappearingMessages = disappearingMessages
        self.accentColor = accentColor
        self.relayCursor = relayCursor
        self.activitySequence = activitySequence
        self.peerBurnedAt = peerBurnedAt
        self.processedIncomingSequences = processedIncomingSequences
        self.authToken = authToken
        self.burnToken = burnToken
    }

    // MARK: - Computed Properties

    /// Total usage percentage (my consumption + peer consumption)
    var usagePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(sendOffset + peerConsumed) / Double(totalBytes)
    }

    /// My usage percentage (bytes I've consumed for sending)
    var myUsagePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(sendOffset) / Double(totalBytes)
    }

    /// Peer's usage percentage (bytes they've consumed)
    var peerUsagePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(peerConsumed) / Double(totalBytes)
    }

    /// Dynamically computed remaining bytes
    var dynamicRemainingBytes: UInt64 {
        let consumed = sendOffset + peerConsumed
        return consumed < totalBytes ? totalBytes - consumed : 0
    }

    var formattedRemaining: String {
        ByteCountFormatter.string(fromByteCount: Int64(dynamicRemainingBytes), countStyle: .binary)
    }

    var isExhausted: Bool {
        dynamicRemainingBytes == 0
    }

    /// Whether the peer has burned this conversation (always immediate burn)
    var isBurned: Bool {
        peerBurnedAt != nil
    }

    var displayName: String {
        if let name = customName, !name.isEmpty {
            return name
        }
        return mnemonicChecksum.prefix(3).joined(separator: " ")
    }

    var avatarInitials: String {
        if let name = customName, !name.isEmpty {
            let words = name.split(separator: " ")
            if words.count >= 2 {
                return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }
        return mnemonicChecksum.first?.prefix(2).uppercased() ?? "??"
    }

    // MARK: - Business Logic

    /// Calculate if there's enough pad remaining for a message
    func canSendMessage(ofLength length: Int) -> Bool {
        return sendOffset + UInt64(length) + peerConsumed <= totalBytes
    }

    /// Calculate the actual pad byte offset for encryption
    func padOffset(forMessageLength messageLength: UInt64) -> UInt64 {
        switch role {
        case .initiator:
            return sendOffset
        case .responder:
            return totalBytes - sendOffset - messageLength
        }
    }

    /// Create a copy with updated send offset after sending a message
    func afterSending(bytes count: UInt64) -> Conversation {
        var copy = self
        copy.sendOffset += count
        copy.remainingBytes = copy.dynamicRemainingBytes
        copy.lastActivity = Date()
        copy.activitySequence += 1
        return copy
    }

    /// Create a copy with updated peer consumption after receiving a message
    func afterReceiving(sequence: UInt64, length: UInt64) -> Conversation {
        var copy = self
        copy.lastActivity = Date()
        copy.processedIncomingSequences.insert(sequence)

        let newPeerConsumed: UInt64
        switch role {
        case .initiator:
            newPeerConsumed = totalBytes - sequence
        case .responder:
            newPeerConsumed = sequence + length
        }

        if newPeerConsumed > copy.peerConsumed {
            copy.peerConsumed = newPeerConsumed
        }

        copy.remainingBytes = copy.dynamicRemainingBytes
        copy.activitySequence += 1
        return copy
    }

    /// Check if this incoming sequence has already been processed
    func hasProcessedIncomingSequence(_ sequence: UInt64) -> Bool {
        processedIncomingSequences.contains(sequence)
    }
}

// MARK: - Factory

extension Conversation {
    /// Create a new conversation from a completed ceremony
    static func fromCeremony(
        padBytes: [UInt8],
        mnemonic: [String],
        role: ConversationRole,
        relayURL: String,
        customName: String? = nil,
        disappearingMessages: DisappearingMessages = .off,
        accentColor: ConversationColor = .indigo,
        authToken: String,
        burnToken: String
    ) -> Conversation {
        let conversationId = deriveConversationId(from: padBytes)

        return Conversation(
            id: conversationId,
            createdAt: Date(),
            lastActivity: Date(),
            remainingBytes: UInt64(padBytes.count),
            totalBytes: UInt64(padBytes.count),
            unreadCount: 0,
            mnemonicChecksum: mnemonic,
            customName: customName,
            role: role,
            sendOffset: 0,
            peerConsumed: 0,
            relayURL: relayURL,
            disappearingMessages: disappearingMessages,
            accentColor: accentColor,
            authToken: authToken,
            burnToken: burnToken
        )
    }

    /// Derive a deterministic conversation ID from pad bytes
    private static func deriveConversationId(from padBytes: [UInt8]) -> String {
        let bytesToHash = Array(padBytes.prefix(64))
        let hash = SHA256.hash(data: Data(bytesToHash))
        let hashBytes = Array(hash.prefix(16))
        return Data(hashBytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Create a copy with a new custom name
    func renamed(to newName: String?) -> Conversation {
        var copy = self
        copy.customName = newName
        return copy
    }

    /// Create a copy with updated relay URL
    func withRelayURL(_ url: String) -> Conversation {
        var copy = self
        copy.relayURL = url
        return copy
    }

    /// Create a copy with updated accent color
    func withAccentColor(_ color: ConversationColor) -> Conversation {
        var copy = self
        copy.accentColor = color
        return copy
    }

    /// Create a copy with updated relay cursor
    func withCursor(_ cursor: String?) -> Conversation {
        var copy = self
        copy.relayCursor = cursor
        return copy
    }
}
