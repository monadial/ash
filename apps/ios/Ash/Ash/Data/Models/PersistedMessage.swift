//
//  PersistedMessage.swift
//  Ash
//
//  SwiftData model for locally persisted messages
//  Messages are stored as encrypted blobs and deleted when conversation is burned
//

import Foundation
import SwiftData

/// SwiftData model for persisted messages
/// Stores messages locally for conversations with persistMessages enabled
@Model
final class PersistedMessage {
    /// Unique message identifier
    @Attribute(.unique) var id: UUID

    /// Conversation this message belongs to
    var conversationId: String

    /// JSON-encoded MessageContent
    var contentData: Data

    /// When the message was created
    var timestamp: Date

    /// Whether this message was sent by the local user
    var isOutgoing: Bool

    /// When the message expires (optional)
    var expiresAt: Date?

    /// Encoded delivery status (0=none, 1=sending, 2=sent, 3=failed)
    var deliveryStatusRaw: Int

    /// Failure reason if deliveryStatusRaw == 3
    var failureReason: String?

    /// Pad sequence (offset) used for this message - used for deduplication
    var sequence: UInt64?

    /// Whether the message content has been securely wiped (pad bytes zeroed)
    var isContentWiped: Bool

    /// Authentication tag (32 bytes) for message integrity verification display
    var authTag: Data?

    init(
        id: UUID,
        conversationId: String,
        contentData: Data,
        timestamp: Date,
        isOutgoing: Bool,
        expiresAt: Date? = nil,
        deliveryStatusRaw: Int = 0,
        failureReason: String? = nil,
        sequence: UInt64? = nil,
        isContentWiped: Bool = false
    ) {
        self.id = id
        self.conversationId = conversationId
        self.contentData = contentData
        self.timestamp = timestamp
        self.isOutgoing = isOutgoing
        self.expiresAt = expiresAt
        self.deliveryStatusRaw = deliveryStatusRaw
        self.failureReason = failureReason
        self.sequence = sequence
        self.isContentWiped = isContentWiped
    }
}

// MARK: - Conversion

extension PersistedMessage {
    /// Create a PersistedMessage from a domain Message
    convenience init(from message: Message, conversationId: String) throws {
        let contentData = try JSONEncoder().encode(message.content)
        let (statusRaw, reason) = message.deliveryStatus.encoded

        self.init(
            id: message.id,
            conversationId: conversationId,
            contentData: contentData,
            timestamp: message.timestamp,
            isOutgoing: message.isOutgoing,
            expiresAt: message.expiresAt,
            deliveryStatusRaw: statusRaw,
            failureReason: reason,
            sequence: message.sequence,
            isContentWiped: message.isContentWiped
        )
        self.authTag = message.authTag.map { Data($0) }
    }

    /// Convert to domain Message
    func toMessage() throws -> Message {
        let content = try JSONDecoder().decode(MessageContent.self, from: contentData)
        let deliveryStatus = DeliveryStatus.decoded(raw: deliveryStatusRaw, reason: failureReason)

        var message = Message(
            id: id,
            content: content,
            timestamp: timestamp,
            isOutgoing: isOutgoing,
            expiresAt: expiresAt,
            deliveryStatus: deliveryStatus,
            sequence: sequence,
            authTag: authTag.map { Array($0) }
        )
        message.isContentWiped = isContentWiped
        return message
    }
}

// MARK: - DeliveryStatus Encoding/Decoding

extension DeliveryStatus {
    /// Encode delivery status to raw integer + optional reason
    var encoded: (raw: Int, reason: String?) {
        switch self {
        case .none: return (0, nil)
        case .sending: return (1, nil)
        case .sent: return (2, nil)
        case .failed(let reason): return (3, reason)
        case .delivered: return (4, nil)
        }
    }

    /// Decode delivery status from raw integer + optional reason
    static func decoded(raw: Int, reason: String?) -> DeliveryStatus {
        switch raw {
        case 0: return .none
        case 1: return .sending
        case 2: return .sent
        case 3: return .failed(reason: reason)
        case 4: return .delivered
        default: return .none
        }
    }
}
