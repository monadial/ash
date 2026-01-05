//
//  SendMessageUseCaseTests.swift
//  AshTests
//
//  Unit tests for SendMessageUseCase, especially sequence calculation
//  for Initiator vs Responder roles.
//
//  The key issue being tested:
//  - Initiator: sequence = consumed_front (offset where key STARTS)
//  - Responder: sequence = total_size - consumed_back - message_size (offset where key STARTS)
//
//  Previously, Responder was incorrectly using next_send_offset BEFORE consume,
//  which returned total_size (e.g., 32768 for a 32KB pad), causing out-of-bounds errors.
//

import Testing
import Foundation
@testable import Ash

// MARK: - SendMessageUseCase Sequence Tests

struct SendMessageUseCaseTests {

    // MARK: - Test Helpers

    private func createConversation(
        role: ConversationRole,
        totalBytes: UInt64 = 32768,  // 32KB like Tiny pad
        sendOffset: UInt64 = 0,
        peerConsumed: UInt64 = 0
    ) -> Conversation {
        let remaining = totalBytes - sendOffset - peerConsumed
        return Conversation(
            id: "test-conversation",
            createdAt: Date(),
            lastActivity: Date(),
            remainingBytes: remaining,
            totalBytes: totalBytes,
            unreadCount: 0,
            mnemonicChecksum: ["alpha", "beta", "gamma", "delta", "epsilon", "zeta"],
            customName: nil,
            role: role,
            sendOffset: sendOffset,
            peerConsumed: peerConsumed,
            relayURL: "https://relay.test",
            authToken: "test-auth-token",
            burnToken: "test-burn-token"
        )
    }

    // MARK: - Initiator Sequence Tests

    @Test func initiator_firstMessage_sequenceIsZero() async throws {
        let padManager = MockPadManager()
        let conversationRepo = MockConversationRepository()
        let cryptoService = MockCryptoService()

        // Create 32KB pad with sequential bytes for verification
        let padBytes: [UInt8] = (0..<32768).map { UInt8($0 % 256) }
        try await padManager.storePad(bytes: padBytes, for: "test-conversation")

        let useCase = SendMessageUseCase(
            padManager: padManager,
            conversationRepository: conversationRepo,
            cryptoService: cryptoService
        )

        let conversation = createConversation(role: .initiator)

        // Send a 3-byte message
        let result = try await useCase.execute(
            content: .text("Hi!"),
            in: conversation
        )

        // Initiator's first message should have sequence = 0
        #expect(result.sequence == 0, "Initiator first message sequence should be 0")

        // Verify key was from bytes [0, 1, 2]
        #expect(cryptoService.lastEncryptKey == [0, 1, 2])
    }

    @Test func initiator_secondMessage_sequenceIncrements() async throws {
        let padManager = MockPadManager()
        let conversationRepo = MockConversationRepository()
        let cryptoService = MockCryptoService()

        let padBytes: [UInt8] = (0..<32768).map { UInt8($0 % 256) }
        try await padManager.storePad(bytes: padBytes, for: "test-conversation")

        let useCase = SendMessageUseCase(
            padManager: padManager,
            conversationRepository: conversationRepo,
            cryptoService: cryptoService
        )

        // First message: 3 bytes
        var conversation = createConversation(role: .initiator)
        let result1 = try await useCase.execute(content: .text("Hi!"), in: conversation)
        #expect(result1.sequence == 0)

        // Second message: 5 bytes (simulate state update)
        conversation = result1.updatedConversation
        let result2 = try await useCase.execute(content: .text("Hello"), in: conversation)
        #expect(result2.sequence == 3, "Second message should start at offset 3")

        // Verify key was from bytes [3, 4, 5, 6, 7]
        #expect(cryptoService.lastEncryptKey == [3, 4, 5, 6, 7])
    }

    @Test func initiator_multipleMessages_sequenceTracksCorrectly() async throws {
        let padManager = MockPadManager()
        let conversationRepo = MockConversationRepository()
        let cryptoService = MockCryptoService()

        let padBytes: [UInt8] = (0..<32768).map { UInt8($0 % 256) }
        try await padManager.storePad(bytes: padBytes, for: "test-conversation")

        let useCase = SendMessageUseCase(
            padManager: padManager,
            conversationRepository: conversationRepo,
            cryptoService: cryptoService
        )

        var conversation = createConversation(role: .initiator)

        // First message: "Hi!" (3 bytes) - sequence 0
        let result1 = try await useCase.execute(content: .text("Hi!"), in: conversation)
        #expect(result1.sequence == 0)
        conversation = result1.updatedConversation

        // Second message: "Hey" (3 bytes) - sequence 3
        let result2 = try await useCase.execute(content: .text("Hey"), in: conversation)
        #expect(result2.sequence == 3)
        conversation = result2.updatedConversation

        // Third message: "Test" (4 bytes) - sequence 6
        let result3 = try await useCase.execute(content: .text("Test"), in: conversation)
        #expect(result3.sequence == 6)
    }

    // MARK: - Responder Sequence Tests (The bug fix)

    @Test func responder_firstMessage_sequenceIsNotTotal() async throws {
        let padManager = MockPadManager()
        let conversationRepo = MockConversationRepository()
        let cryptoService = MockCryptoService()

        // 32KB pad
        let padBytes: [UInt8] = (0..<32768).map { UInt8($0 % 256) }
        try await padManager.storePad(bytes: padBytes, for: "test-conversation")

        let useCase = SendMessageUseCase(
            padManager: padManager,
            conversationRepository: conversationRepo,
            cryptoService: cryptoService
        )

        let conversation = createConversation(role: .responder)

        // Send a 3-byte message
        let result = try await useCase.execute(
            content: .text("Hi!"),
            in: conversation
        )

        // BUG FIX: Responder's first message should have sequence = 32768 - 3 = 32765
        // NOT 32768 (which would be out of bounds!)
        #expect(result.sequence == 32765, "Responder first message sequence should be 32765, not 32768")

        // Verify key was from bytes [32765, 32766, 32767] (last 3 bytes)
        #expect(cryptoService.lastEncryptKey == [253, 254, 255])  // 32765 % 256, 32766 % 256, 32767 % 256
    }

    @Test func responder_sequenceIsWithinPadBounds() async throws {
        let padManager = MockPadManager()
        let conversationRepo = MockConversationRepository()
        let cryptoService = MockCryptoService()

        let padSize: UInt64 = 32768
        let padBytes: [UInt8] = (0..<Int(padSize)).map { UInt8($0 % 256) }
        try await padManager.storePad(bytes: padBytes, for: "test-conversation")

        let useCase = SendMessageUseCase(
            padManager: padManager,
            conversationRepository: conversationRepo,
            cryptoService: cryptoService
        )

        let conversation = createConversation(role: .responder, totalBytes: padSize)
        let messageSize = 3

        let result = try await useCase.execute(
            content: .text("Hi!"),
            in: conversation
        )

        // Sequence should be valid: sequence + messageSize <= padSize
        #expect(result.sequence + UInt64(messageSize) <= padSize,
               "Sequence \(result.sequence) + \(messageSize) should be <= \(padSize)")

        // Sequence should NOT be equal to padSize (the old bug)
        #expect(result.sequence != padSize,
               "Sequence should not equal padSize (\(padSize))")
    }

    @Test func responder_secondMessage_sequenceDecrements() async throws {
        let padManager = MockPadManager()
        let conversationRepo = MockConversationRepository()
        let cryptoService = MockCryptoService()

        let padBytes: [UInt8] = (0..<32768).map { UInt8($0 % 256) }
        try await padManager.storePad(bytes: padBytes, for: "test-conversation")

        let useCase = SendMessageUseCase(
            padManager: padManager,
            conversationRepository: conversationRepo,
            cryptoService: cryptoService
        )

        // First message: 3 bytes
        var conversation = createConversation(role: .responder)
        let result1 = try await useCase.execute(content: .text("Hi!"), in: conversation)
        #expect(result1.sequence == 32765)  // 32768 - 0 - 3

        // Second message: 5 bytes
        conversation = result1.updatedConversation
        let result2 = try await useCase.execute(content: .text("Hello"), in: conversation)
        #expect(result2.sequence == 32760)  // 32768 - 3 - 5 = 32760

        // Third message: 4 bytes
        conversation = result2.updatedConversation
        let result3 = try await useCase.execute(content: .text("Test"), in: conversation)
        #expect(result3.sequence == 32756)  // 32768 - 8 - 4 = 32756
    }

    // MARK: - Cross-party Communication Tests

    @Test func initiatorAndResponder_sequencesDontOverlap() async throws {
        // This test simulates a full conversation where Alice (initiator)
        // and Bob (responder) send messages, verifying their sequences
        // don't overlap and point to distinct pad regions.

        let padSize: UInt64 = 1000
        let padBytes: [UInt8] = (0..<Int(padSize)).map { UInt8($0 % 256) }

        // Alice (Initiator) setup
        let alicePadManager = MockPadManager()
        let aliceConvRepo = MockConversationRepository()
        let aliceCrypto = MockCryptoService()
        try await alicePadManager.storePad(bytes: padBytes, for: "test-conversation")
        let aliceUseCase = SendMessageUseCase(
            padManager: alicePadManager,
            conversationRepository: aliceConvRepo,
            cryptoService: aliceCrypto
        )

        // Bob (Responder) setup
        let bobPadManager = MockPadManager()
        let bobConvRepo = MockConversationRepository()
        let bobCrypto = MockCryptoService()
        try await bobPadManager.storePad(bytes: padBytes, for: "test-conversation")
        let bobUseCase = SendMessageUseCase(
            padManager: bobPadManager,
            conversationRepository: bobConvRepo,
            cryptoService: bobCrypto
        )

        var aliceConversation = createConversation(role: .initiator, totalBytes: padSize)
        var bobConversation = createConversation(role: .responder, totalBytes: padSize)

        // Alice sends (3 bytes) - should use sequence 0
        let aliceResult1 = try await aliceUseCase.execute(content: .text("Hi!"), in: aliceConversation)
        aliceConversation = aliceResult1.updatedConversation

        // Bob sends (3 bytes) - should use sequence 997 (1000 - 0 - 3)
        let bobResult1 = try await bobUseCase.execute(content: .text("Hi!"), in: bobConversation)
        bobConversation = bobResult1.updatedConversation

        // Alice sends again (5 bytes) - should use sequence 3
        let aliceResult2 = try await aliceUseCase.execute(content: .text("Hello"), in: aliceConversation)

        // Bob sends again (5 bytes) - should use sequence 992 (1000 - 3 - 5)
        let bobResult2 = try await bobUseCase.execute(content: .text("Hello"), in: bobConversation)

        // Verify sequences
        #expect(aliceResult1.sequence == 0)
        #expect(aliceResult2.sequence == 3)
        #expect(bobResult1.sequence == 997)  // 1000 - 0 - 3
        #expect(bobResult2.sequence == 992)  // 1000 - 3 - 5

        // Verify no overlap: Alice uses [0-7], Bob uses [992-999]
        let aliceRanges = [(0, 2), (3, 7)]  // First msg [0-2], second [3-7]
        let bobRanges = [(997, 999), (992, 996)]  // First msg [997-999], second [992-996]

        for aliceRange in aliceRanges {
            for bobRange in bobRanges {
                let overlap = max(aliceRange.0, bobRange.0) <= min(aliceRange.1, bobRange.1)
                #expect(!overlap, "Alice range \(aliceRange) and Bob range \(bobRange) should not overlap")
            }
        }
    }

    @Test func responder_canDecryptWithCorrectOffset() async throws {
        // This test verifies that when Bob (responder) sends a message with
        // sequence X, Alice (initiator) can decrypt it by reading bytes starting
        // at offset X.

        let padSize: UInt64 = 100
        let padBytes: [UInt8] = (0..<Int(padSize)).map { UInt8($0 % 256) }

        let padManager = MockPadManager()
        let conversationRepo = MockConversationRepository()
        let cryptoService = MockCryptoService()
        try await padManager.storePad(bytes: padBytes, for: "test-conversation")

        let useCase = SendMessageUseCase(
            padManager: padManager,
            conversationRepository: conversationRepo,
            cryptoService: cryptoService
        )

        let conversation = createConversation(role: .responder, totalBytes: padSize)

        // Bob sends "Hi!" (3 bytes)
        let result = try await useCase.execute(content: .text("Hi!"), in: conversation)
        let sequence = result.sequence

        // Sequence should be 97 (100 - 0 - 3)
        #expect(sequence == 97)

        // Alice would decrypt by reading bytes at offset 97
        // Let's verify the key bytes are correct
        let decryptionKey = try await padManager.getBytesForDecryption(
            offset: sequence,
            length: 3,
            for: "test-conversation"
        )

        // Bytes at [97, 98, 99] should be [97, 98, 99] (since padBytes[i] = i % 256)
        #expect(decryptionKey == [97, 98, 99])

        // The encryption key used should match
        #expect(cryptoService.lastEncryptKey == [97, 98, 99])
    }

    // MARK: - Edge Cases

    @Test func responder_singleByte_message() async throws {
        let padManager = MockPadManager()
        let conversationRepo = MockConversationRepository()
        let cryptoService = MockCryptoService()

        let padSize: UInt64 = 100
        let padBytes: [UInt8] = (0..<Int(padSize)).map { UInt8($0 % 256) }
        try await padManager.storePad(bytes: padBytes, for: "test-conversation")

        let useCase = SendMessageUseCase(
            padManager: padManager,
            conversationRepository: conversationRepo,
            cryptoService: cryptoService
        )

        let conversation = createConversation(role: .responder, totalBytes: padSize)

        // Single byte message
        let result = try await useCase.execute(content: .text("X"), in: conversation)

        // Sequence should be 99 (100 - 0 - 1)
        #expect(result.sequence == 99)
        #expect(cryptoService.lastEncryptKey == [99])
    }

    @Test func responder_largeMessage() async throws {
        let padManager = MockPadManager()
        let conversationRepo = MockConversationRepository()
        let cryptoService = MockCryptoService()

        let padSize: UInt64 = 1000
        let padBytes: [UInt8] = (0..<Int(padSize)).map { UInt8($0 % 256) }
        try await padManager.storePad(bytes: padBytes, for: "test-conversation")

        let useCase = SendMessageUseCase(
            padManager: padManager,
            conversationRepository: conversationRepo,
            cryptoService: cryptoService
        )

        let conversation = createConversation(role: .responder, totalBytes: padSize)

        // 100-byte message
        let longText = String(repeating: "X", count: 100)
        let result = try await useCase.execute(content: .text(longText), in: conversation)

        // Sequence should be 900 (1000 - 0 - 100)
        #expect(result.sequence == 900)
    }

    @Test func responder_afterPeerConsumption() async throws {
        let padManager = MockPadManager()
        let conversationRepo = MockConversationRepository()
        let cryptoService = MockCryptoService()

        let padSize: UInt64 = 1000
        let padBytes: [UInt8] = (0..<Int(padSize)).map { UInt8($0 % 256) }
        try await padManager.storePad(bytes: padBytes, for: "test-conversation")

        // Simulate peer (initiator) having consumed 200 bytes
        try await padManager.updatePeerConsumption(peerRole: .initiator, consumed: 200, for: "test-conversation")

        let useCase = SendMessageUseCase(
            padManager: padManager,
            conversationRepository: conversationRepo,
            cryptoService: cryptoService
        )

        // Responder with sendOffset=0 but aware of peer consumption
        let conversation = createConversation(
            role: .responder,
            totalBytes: padSize,
            sendOffset: 0,
            peerConsumed: 200
        )

        // Send 3-byte message
        let result = try await useCase.execute(content: .text("Hi!"), in: conversation)

        // Sequence should be 997 (1000 - 0 - 3)
        // The peer consumption affects remaining bytes but not our sequence calculation
        #expect(result.sequence == 997)
    }

    // MARK: - Regression Test: The Original Bug

    @Test func responder_sequenceNotEqualToPadSize_regression() async throws {
        // This is the exact regression test for the bug:
        // Before fix: Responder's first message had sequence = 32768 (pad size)
        // After fix: Responder's first message has sequence = 32765 (pad size - msg length)

        let padManager = MockPadManager()
        let conversationRepo = MockConversationRepository()
        let cryptoService = MockCryptoService()

        // Use exact Tiny pad size
        let padSize: UInt64 = 32768
        let padBytes: [UInt8] = Array(repeating: 0xAB, count: Int(padSize))
        try await padManager.storePad(bytes: padBytes, for: "test-conversation")

        let useCase = SendMessageUseCase(
            padManager: padManager,
            conversationRepository: conversationRepo,
            cryptoService: cryptoService
        )

        let conversation = createConversation(role: .responder, totalBytes: padSize)

        // Send 3-byte message (like "Hi!")
        let result = try await useCase.execute(content: .text("abc"), in: conversation)

        // THE FIX: sequence should be 32765, NOT 32768
        #expect(result.sequence != padSize,
               "REGRESSION: Sequence should NOT equal pad size! Got \(result.sequence)")
        #expect(result.sequence == padSize - 3,
               "Sequence should be padSize - messageLength = \(padSize - 3), got \(result.sequence)")

        // Verify it's a valid offset: sequence + length <= padSize
        let messageLength: UInt64 = 3
        #expect(result.sequence + messageLength <= padSize,
               "Offset \(result.sequence) + length \(messageLength) should be <= \(padSize)")
    }
}
