//
//  ScreenshotHelper.swift
//  Ash
//
//  Sample data for screenshot previews.
//  Used by #Preview macros in the actual screen files.
//

import SwiftUI

// MARK: - Sample Conversations

extension Conversation {
    /// Sample conversations for screenshot previews
    static let screenshotSamples: [Conversation] = [
        Conversation(
            id: "screenshot-1",
            createdAt: Date().addingTimeInterval(-86400 * 7),
            lastActivity: Date().addingTimeInterval(-180),
            remainingBytes: 180_000,
            totalBytes: 262_144,
            unreadCount: 2,
            mnemonicChecksum: ["whisper", "phoenix", "ember", "shadow", "cipher", "vault"],
            customName: "Alice",
            role: .initiator,
            sendOffset: 45_000,
            peerConsumed: 37_144,
            relayURL: "https://eu.relay.ashprotocol.app",
            messageRetention: .oneHour,
            disappearingMessages: .fiveMinutes,
            accentColor: .indigo,
            authToken: "sample",
            burnToken: "sample"
        ),
        Conversation(
            id: "screenshot-2",
            createdAt: Date().addingTimeInterval(-86400 * 3),
            lastActivity: Date().addingTimeInterval(-3600),
            remainingBytes: 900_000,
            totalBytes: 1_048_576,
            unreadCount: 0,
            mnemonicChecksum: ["forge", "silver", "dawn", "anchor", "storm", "raven"],
            customName: "Bob",
            role: .responder,
            sendOffset: 80_000,
            peerConsumed: 68_576,
            relayURL: "https://eu.relay.ashprotocol.app",
            messageRetention: .twelveHours,
            disappearingMessages: .off,
            accentColor: .teal,
            authToken: "sample",
            burnToken: "sample"
        ),
        Conversation(
            id: "screenshot-3",
            createdAt: Date().addingTimeInterval(-86400),
            lastActivity: Date().addingTimeInterval(-7200),
            remainingBytes: 55_000,
            totalBytes: 65_536,
            unreadCount: 0,
            mnemonicChecksum: ["crystal", "night", "flame", "echo", "delta", "omega"],
            customName: nil,
            role: .initiator,
            sendOffset: 6_000,
            peerConsumed: 4_536,
            relayURL: "https://eu.relay.ashprotocol.app",
            messageRetention: .fiveMinutes,
            disappearingMessages: .thirtySeconds,
            accentColor: .purple,
            authToken: "sample",
            burnToken: "sample"
        ),
        Conversation(
            id: "screenshot-4",
            createdAt: Date().addingTimeInterval(-86400 * 14),
            lastActivity: Date().addingTimeInterval(-86400),
            remainingBytes: 12_000,
            totalBytes: 262_144,
            unreadCount: 1,
            mnemonicChecksum: ["beacon", "frost", "river", "spark", "iron", "sage"],
            customName: "Secure Contact",
            role: .responder,
            sendOffset: 125_000,
            peerConsumed: 125_144,
            relayURL: "https://eu.relay.ashprotocol.app",
            messageRetention: .sevenDays,
            disappearingMessages: .oneHour,
            accentColor: .orange,
            authToken: "sample",
            burnToken: "sample"
        )
    ]
}

// MARK: - Sample Messages

extension Message {
    /// Sample messages for screenshot previews
    static let screenshotSamples: [Message] = [
        Message(
            id: UUID(),
            content: .text("Hey, I have something important to share with you."),
            timestamp: Date().addingTimeInterval(-3600),
            isOutgoing: false,
            expiresAt: nil,
            serverExpiresAt: nil,
            deliveryStatus: .none,
            sequence: 1000,
            blobId: UUID(),
            authTag: nil
        ),
        Message(
            id: UUID(),
            content: .text("Of course, this channel is completely secure. What's on your mind?"),
            timestamp: Date().addingTimeInterval(-3500),
            isOutgoing: true,
            expiresAt: nil,
            serverExpiresAt: nil,
            deliveryStatus: .delivered,
            sequence: 2000,
            blobId: UUID(),
            authTag: nil
        ),
        Message(
            id: UUID(),
            content: .text("The documents are ready. We can discuss the details here safely."),
            timestamp: Date().addingTimeInterval(-3400),
            isOutgoing: false,
            expiresAt: nil,
            serverExpiresAt: nil,
            deliveryStatus: .none,
            sequence: 1100,
            blobId: UUID(),
            authTag: nil
        ),
        Message(
            id: UUID(),
            content: .text("Perfect. Remember, once we're done, burn this conversation."),
            timestamp: Date().addingTimeInterval(-3300),
            isOutgoing: true,
            expiresAt: nil,
            serverExpiresAt: nil,
            deliveryStatus: .delivered,
            sequence: 2100,
            blobId: UUID(),
            authTag: nil
        ),
        Message(
            id: UUID(),
            content: .text("Understood. OTP encryption means no one can ever read these."),
            timestamp: Date().addingTimeInterval(-3200),
            isOutgoing: false,
            expiresAt: nil,
            serverExpiresAt: nil,
            deliveryStatus: .none,
            sequence: 1200,
            blobId: UUID(),
            authTag: nil
        ),
        Message(
            id: UUID(),
            content: .location(latitude: 48.8566, longitude: 2.3522),
            timestamp: Date().addingTimeInterval(-300),
            isOutgoing: true,
            expiresAt: nil,
            serverExpiresAt: nil,
            deliveryStatus: .delivered,
            sequence: 2200,
            blobId: UUID(),
            authTag: nil
        ),
        Message(
            id: UUID(),
            content: .text("I'll meet you there. Stay safe."),
            timestamp: Date().addingTimeInterval(-60),
            isOutgoing: false,
            expiresAt: Date().addingTimeInterval(240),
            serverExpiresAt: nil,
            deliveryStatus: .none,
            sequence: 1300,
            blobId: UUID(),
            authTag: nil
        )
    ]
}
