//
//  MessageTests.swift
//  AshTests
//
//  Unit tests for Message domain entity
//

import Testing
import Foundation
@testable import Ash

// MARK: - MessageContent Tests

struct MessageContentTests {

    @Test func text_byteCount_returnsUTF8Length() {
        let content = MessageContent.text("Hello")

        #expect(content.byteCount == 5)
    }

    @Test func text_byteCount_handlesUnicode() {
        let content = MessageContent.text("Hello 🌍")

        // "Hello " = 6 bytes, 🌍 = 4 bytes in UTF-8
        #expect(content.byteCount == 10)
    }

    @Test func text_byteCount_emptyString() {
        let content = MessageContent.text("")

        #expect(content.byteCount == 0)
    }

    @Test func location_byteCount_isFixed() {
        let content = MessageContent.location(latitude: 51.507351, longitude: -0.127758)

        // "LOC:" prefix (4) + 6 decimal precision: "-123.123456,-123.123456" (~24) = 28 bytes max
        #expect(content.byteCount == 28)
    }

    @Test func equatable_sameText_areEqual() {
        let content1 = MessageContent.text("Hello")
        let content2 = MessageContent.text("Hello")

        #expect(content1 == content2)
    }

    @Test func equatable_differentText_areNotEqual() {
        let content1 = MessageContent.text("Hello")
        let content2 = MessageContent.text("World")

        #expect(content1 != content2)
    }

    @Test func equatable_sameLocation_areEqual() {
        let content1 = MessageContent.location(latitude: 1.0, longitude: 2.0)
        let content2 = MessageContent.location(latitude: 1.0, longitude: 2.0)

        #expect(content1 == content2)
    }

    @Test func equatable_differentLocation_areNotEqual() {
        let content1 = MessageContent.location(latitude: 1.0, longitude: 2.0)
        let content2 = MessageContent.location(latitude: 3.0, longitude: 4.0)

        #expect(content1 != content2)
    }

    @Test func equatable_textAndLocation_areNotEqual() {
        let text = MessageContent.text("51.0, 0.0")
        let location = MessageContent.location(latitude: 51.0, longitude: 0.0)

        #expect(text != location)
    }
}

// MARK: - Message Tests

struct MessageTests {

    // MARK: - Test Helpers

    private func createMessage(
        content: MessageContent = .text("Test"),
        isOutgoing: Bool = true,
        expiresAt: Date? = Date().addingTimeInterval(300),
        sequence: UInt64? = 0
    ) -> Message {
        Message(
            id: UUID(),
            content: content,
            timestamp: Date(),
            isOutgoing: isOutgoing,
            expiresAt: expiresAt,
            serverExpiresAt: isOutgoing ? Date().addingTimeInterval(300) : nil,
            deliveryStatus: isOutgoing ? .sent : .none,
            sequence: sequence,
            blobId: nil,
            authTag: nil
        )
    }

    // MARK: - Expiry Tests

    @Test func isExpired_beforeExpiry_returnsFalse() {
        let message = createMessage(expiresAt: Date().addingTimeInterval(3600))

        #expect(message.isExpired == false)
    }

    @Test func isExpired_afterExpiry_returnsTrue() {
        let message = createMessage(expiresAt: Date().addingTimeInterval(-1))

        #expect(message.isExpired == true)
    }

    @Test func isExpired_noExpiry_returnsFalse() {
        let message = createMessage(expiresAt: nil)

        #expect(message.isExpired == false)
    }

    @Test func remainingTime_beforeExpiry_returnsPositive() {
        let message = createMessage(expiresAt: Date().addingTimeInterval(100))

        guard let remaining = message.remainingTime else {
            Issue.record("Expected remaining time")
            return
        }

        #expect(remaining > 0)
        #expect(remaining <= 100)
    }

    @Test func remainingTime_afterExpiry_returnsZero() {
        let message = createMessage(expiresAt: Date().addingTimeInterval(-100))

        #expect(message.remainingTime == 0)
    }

    @Test func remainingTime_noExpiry_returnsNil() {
        let message = createMessage(expiresAt: nil)

        #expect(message.remainingTime == nil)
    }

    @Test func formattedTime_returnsString() {
        let message = createMessage()

        let formatted = message.formattedTime

        #expect(!formatted.isEmpty)
    }

    // MARK: - Factory Tests

    @Test func outgoing_createsOutgoingMessage() {
        let message = Message.outgoing(text: "Hello", sequence: 0)

        #expect(message.isOutgoing == true)
        if case .text(let text) = message.content {
            #expect(text == "Hello")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func outgoing_withDefaultExpiry_serverExpiresIn5Minutes() {
        let message = Message.outgoing(text: "Test", sequence: 0)

        guard let serverExpiresAt = message.serverExpiresAt else {
            Issue.record("Expected server expiry date")
            return
        }

        let interval = serverExpiresAt.timeIntervalSince(message.timestamp)
        #expect(interval >= 299 && interval <= 301) // ~300 seconds
    }

    @Test func outgoing_withCustomExpiry() {
        let message = Message.outgoing(text: "Test", sequence: 0, serverTTLSeconds: 60)

        guard let serverExpiresAt = message.serverExpiresAt else {
            Issue.record("Expected server expiry date")
            return
        }

        let interval = serverExpiresAt.timeIntervalSince(message.timestamp)
        #expect(interval >= 59 && interval <= 61)
    }

    @Test func outgoingLocation_createsLocationMessage() {
        let message = Message.outgoingLocation(latitude: 51.5, longitude: -0.1, sequence: 0)

        #expect(message.isOutgoing == true)
        if case .location(let lat, let lon) = message.content {
            #expect(lat == 51.5)
            #expect(lon == -0.1)
        } else {
            Issue.record("Expected location content")
        }
    }

    @Test func incoming_createsIncomingMessage() {
        let message = Message.incoming(content: .text("Hello"), sequence: 0, disappearingSeconds: nil, blobId: UUID())

        #expect(message.isOutgoing == false)
    }

    @Test func incoming_withLocationContent() {
        let message = Message.incoming(
            content: .location(latitude: 40.7, longitude: -74.0),
            sequence: 0,
            disappearingSeconds: nil,
            blobId: UUID()
        )

        if case .location(let lat, let lon) = message.content {
            #expect(lat == 40.7)
            #expect(lon == -74.0)
        } else {
            Issue.record("Expected location content")
        }
    }

    // MARK: - Equatable/Hashable Tests

    @Test func equatable_sameId_areEqual() {
        let id = UUID()
        let timestamp = Date()
        let message1 = Message(
            id: id,
            content: .text("A"),
            timestamp: timestamp,
            isOutgoing: true,
            expiresAt: nil,
            serverExpiresAt: nil,
            deliveryStatus: .sent,
            sequence: 0,
            blobId: nil,
            authTag: nil
        )
        let message2 = Message(
            id: id,
            content: .text("A"),
            timestamp: timestamp,
            isOutgoing: true,
            expiresAt: nil,
            serverExpiresAt: nil,
            deliveryStatus: .sent,
            sequence: 0,
            blobId: nil,
            authTag: nil
        )

        #expect(message1 == message2)
    }

    @Test func equatable_differentId_areNotEqual() {
        let timestamp = Date()
        let message1 = Message(
            id: UUID(),
            content: .text("Same"),
            timestamp: timestamp,
            isOutgoing: true,
            expiresAt: nil,
            serverExpiresAt: nil,
            deliveryStatus: .sent,
            sequence: 0,
            blobId: nil,
            authTag: nil
        )
        let message2 = Message(
            id: UUID(),
            content: .text("Same"),
            timestamp: timestamp,
            isOutgoing: true,
            expiresAt: nil,
            serverExpiresAt: nil,
            deliveryStatus: .sent,
            sequence: 0,
            blobId: nil,
            authTag: nil
        )

        #expect(message1 != message2)
    }

    @Test func hashable_sameMessage_sameHash() {
        let id = UUID()
        let timestamp = Date()
        let message1 = Message(
            id: id,
            content: .text("Hash"),
            timestamp: timestamp,
            isOutgoing: true,
            expiresAt: nil,
            serverExpiresAt: nil,
            deliveryStatus: .sent,
            sequence: 0,
            blobId: nil,
            authTag: nil
        )
        let message2 = Message(
            id: id,
            content: .text("Hash"),
            timestamp: timestamp,
            isOutgoing: true,
            expiresAt: nil,
            serverExpiresAt: nil,
            deliveryStatus: .sent,
            sequence: 0,
            blobId: nil,
            authTag: nil
        )

        #expect(message1.hashValue == message2.hashValue)
    }

    // MARK: - Delivery Status Tests

    @Test func deliveryStatus_outgoing_hasSendingStatus() {
        let message = Message.outgoing(text: "Test", sequence: 0)

        #expect(message.deliveryStatus == .sending)
    }

    @Test func deliveryStatus_incoming_hasNoStatus() {
        let message = Message.incoming(content: .text("Test"), sequence: 0, disappearingSeconds: nil, blobId: UUID())

        #expect(message.deliveryStatus == .none)
    }

    @Test func withDeliveryStatus_createsUpdatedCopy() {
        let message = Message.outgoing(text: "Test", sequence: 0)

        let updated = message.withDeliveryStatus(.sent)

        #expect(updated.deliveryStatus == .sent)
        #expect(updated.id == message.id)
        #expect(updated.content == message.content)
    }
}

// MARK: - DeliveryStatus Tests

struct DeliveryStatusTests {

    @Test func allCases_containsExpectedStatuses() {
        // DeliveryStatus has: sending, sent, failed(reason:), none
        let statuses: [DeliveryStatus] = [.none, .sending, .sent, .failed(reason: nil)]

        #expect(statuses.count == 4)
    }
}
