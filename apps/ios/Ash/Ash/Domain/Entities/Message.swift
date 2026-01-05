//
//  Message.swift
//  Ash
//
//  Domain Entity - Ephemeral message
//

import Foundation

// MARK: - Message Content

/// Content types that can be sent in a message
enum MessageContent: Equatable, Hashable, Sendable, Codable {
    case text(String)
    case location(latitude: Double, longitude: Double)

    var byteCount: Int {
        switch self {
        case .text(let text):
            return text.utf8.count
        case .location:
            // "LOC:" prefix (4) + 6 decimal precision: "-123.123456,-123.123456" (~24) = 28 bytes max
            return 28
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, text, latitude, longitude
    }

    private enum ContentType: String, Codable {
        case text, location
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)
        switch type {
        case .text:
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case .location:
            let latitude = try container.decode(Double.self, forKey: .latitude)
            let longitude = try container.decode(Double.self, forKey: .longitude)
            self = .location(latitude: latitude, longitude: longitude)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(ContentType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .location(let latitude, let longitude):
            try container.encode(ContentType.location, forKey: .type)
            try container.encode(latitude, forKey: .latitude)
            try container.encode(longitude, forKey: .longitude)
        }
    }
}

// MARK: - Delivery Status

/// Delivery status for outgoing messages
enum DeliveryStatus: Equatable, Hashable, Sendable {
    case sending
    case sent
    case failed(reason: String?)
    case none  // For incoming messages
}

// MARK: - Message

/// Represents an ephemeral message in a conversation
struct Message: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let content: MessageContent
    let timestamp: Date
    let isOutgoing: Bool
    let expiresAt: Date?
    var deliveryStatus: DeliveryStatus
    /// Pad sequence (offset) used for this message - used for deduplication
    let sequence: UInt64?

    // MARK: - Computed Properties

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }

    var remainingTime: TimeInterval? {
        guard let expiresAt else { return nil }
        return max(0, expiresAt.timeIntervalSinceNow)
    }

    var formattedTime: String {
        timestamp.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Factory

extension Message {
    /// Create an outgoing text message
    static func outgoing(
        text: String,
        sequence: UInt64,
        expiresIn seconds: TimeInterval = 300
    ) -> Message {
        Message(
            id: UUID(),
            content: .text(text),
            timestamp: Date(),
            isOutgoing: true,
            expiresAt: Date().addingTimeInterval(seconds),
            deliveryStatus: .sending,
            sequence: sequence
        )
    }

    /// Create an outgoing location message
    static func outgoingLocation(
        latitude: Double,
        longitude: Double,
        sequence: UInt64,
        expiresIn seconds: TimeInterval = 300
    ) -> Message {
        Message(
            id: UUID(),
            content: .location(latitude: latitude, longitude: longitude),
            timestamp: Date(),
            isOutgoing: true,
            expiresAt: Date().addingTimeInterval(seconds),
            deliveryStatus: .sending,
            sequence: sequence
        )
    }

    /// Create an incoming message
    static func incoming(
        content: MessageContent,
        sequence: UInt64,
        expiresIn seconds: TimeInterval = 300
    ) -> Message {
        Message(
            id: UUID(),
            content: content,
            timestamp: Date(),
            isOutgoing: false,
            expiresAt: Date().addingTimeInterval(seconds),
            deliveryStatus: .none,
            sequence: sequence
        )
    }

    /// Create a copy with updated delivery status
    func withDeliveryStatus(_ status: DeliveryStatus) -> Message {
        Message(
            id: id,
            content: content,
            timestamp: timestamp,
            isOutgoing: isOutgoing,
            expiresAt: expiresAt,
            deliveryStatus: status,
            sequence: sequence
        )
    }
}

// MARK: - Comparable

extension Message: Comparable {
    /// Sort messages by timestamp (oldest first)
    static func < (lhs: Message, rhs: Message) -> Bool {
        lhs.timestamp < rhs.timestamp
    }
}
