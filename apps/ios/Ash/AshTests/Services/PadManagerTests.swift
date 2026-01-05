//
//  PadManagerTests.swift
//  AshTests
//
//  Unit tests for PadManager service that wraps Rust Pad
//

import Testing
import Foundation
@testable import Ash

// MARK: - PadManager Tests

struct PadManagerTests {

    // MARK: - Store and Load

    @Test func storePad_savesToKeychain() async throws {
        let keychain = MockKeychainService()
        let padManager = PadManager(keychainService: keychain)
        let conversationId = "test-conversation"
        let padBytes: [UInt8] = Array(repeating: 0xAB, count: 1000)

        try await padManager.storePad(bytes: padBytes, for: conversationId)

        // Verify it was stored
        let data = try keychain.retrieve(for: "pad.\(conversationId)")
        #expect(data != nil)
    }

    @Test func getPadState_afterStore_returnsCorrectState() async throws {
        let keychain = MockKeychainService()
        let padManager = PadManager(keychainService: keychain)
        let conversationId = "test-conversation"
        let padBytes: [UInt8] = Array(repeating: 0xAB, count: 1000)

        try await padManager.storePad(bytes: padBytes, for: conversationId)
        let state = try await padManager.getPadState(for: conversationId)

        #expect(state.totalBytes == 1000)
        #expect(state.consumedFront == 0)
        #expect(state.consumedBack == 0)
        #expect(state.remaining == 1000)
        #expect(state.isExhausted == false)
    }

    // MARK: - Can Send (Dynamic Allocation)

    @Test func canSend_freshPad_returnsTrue() async throws {
        let keychain = MockKeychainService()
        let padManager = PadManager(keychainService: keychain)
        let conversationId = "test-conversation"
        let padBytes: [UInt8] = Array(repeating: 0xAB, count: 1000)

        try await padManager.storePad(bytes: padBytes, for: conversationId)

        // Both roles can send up to full pad size
        let canSendInitiator = try await padManager.canSend(length: 1000, role: .initiator, for: conversationId)
        let canSendResponder = try await padManager.canSend(length: 1000, role: .responder, for: conversationId)

        #expect(canSendInitiator == true)
        #expect(canSendResponder == true)
    }

    @Test func canSend_exceedsPadSize_returnsFalse() async throws {
        let keychain = MockKeychainService()
        let padManager = PadManager(keychainService: keychain)
        let conversationId = "test-conversation"
        let padBytes: [UInt8] = Array(repeating: 0xAB, count: 1000)

        try await padManager.storePad(bytes: padBytes, for: conversationId)

        let canSend = try await padManager.canSend(length: 1001, role: .initiator, for: conversationId)

        #expect(canSend == false)
    }

    // MARK: - Asymmetric Allocation (Alice 20%, Bob 80%)

    @Test func asymmetricAllocation_alice20_bob80() async throws {
        let keychain = MockKeychainService()
        let padManager = PadManager(keychainService: keychain)
        let conversationId = "test-conversation"
        let padBytes: [UInt8] = Array(repeating: 0xAB, count: 1000)

        try await padManager.storePad(bytes: padBytes, for: conversationId)

        // Alice (Initiator) consumes 200 bytes (20%)
        _ = try await padManager.consumeForSending(length: 200, role: .initiator, for: conversationId)

        // Check Alice consumed from front
        let state1 = try await padManager.getPadState(for: conversationId)
        #expect(state1.consumedFront == 200)
        #expect(state1.consumedBack == 0)
        #expect(state1.remaining == 800)

        // Bob (Responder) can consume remaining 800 bytes (80%)
        let canBobSend = try await padManager.canSend(length: 800, role: .responder, for: conversationId)
        #expect(canBobSend == true)

        _ = try await padManager.consumeForSending(length: 800, role: .responder, for: conversationId)

        // Pad is now exhausted
        let state2 = try await padManager.getPadState(for: conversationId)
        #expect(state2.consumedFront == 200)
        #expect(state2.consumedBack == 800)
        #expect(state2.remaining == 0)
        #expect(state2.isExhausted == true)
    }

    @Test func asymmetricAllocation_bob90_alice10() async throws {
        let keychain = MockKeychainService()
        let padManager = PadManager(keychainService: keychain)
        let conversationId = "test-conversation"
        let padBytes: [UInt8] = Array(repeating: 0xCD, count: 1000)

        try await padManager.storePad(bytes: padBytes, for: conversationId)

        // Bob (Responder) consumes 900 bytes first (90%)
        _ = try await padManager.consumeForSending(length: 900, role: .responder, for: conversationId)

        let state1 = try await padManager.getPadState(for: conversationId)
        #expect(state1.consumedBack == 900)
        #expect(state1.remaining == 100)

        // Alice (Initiator) can only consume remaining 100 bytes (10%)
        let canAliceSend100 = try await padManager.canSend(length: 100, role: .initiator, for: conversationId)
        let canAliceSend101 = try await padManager.canSend(length: 101, role: .initiator, for: conversationId)

        #expect(canAliceSend100 == true)
        #expect(canAliceSend101 == false)
    }

    // MARK: - Send Offset Tracking

    @Test func nextSendOffset_initiator_tracksCorrectly() async throws {
        let keychain = MockKeychainService()
        let padManager = PadManager(keychainService: keychain)
        let conversationId = "test-conversation"
        let padBytes: [UInt8] = Array(repeating: 0xAB, count: 1000)

        try await padManager.storePad(bytes: padBytes, for: conversationId)

        // Initial offset for initiator is 0
        let offset1 = try await padManager.nextSendOffset(role: .initiator, for: conversationId)
        #expect(offset1 == 0)

        // After consuming 100 bytes, offset is 100
        _ = try await padManager.consumeForSending(length: 100, role: .initiator, for: conversationId)
        let offset2 = try await padManager.nextSendOffset(role: .initiator, for: conversationId)
        #expect(offset2 == 100)

        // After consuming 50 more bytes, offset is 150
        _ = try await padManager.consumeForSending(length: 50, role: .initiator, for: conversationId)
        let offset3 = try await padManager.nextSendOffset(role: .initiator, for: conversationId)
        #expect(offset3 == 150)
    }

    @Test func nextSendOffset_responder_tracksCorrectly() async throws {
        let keychain = MockKeychainService()
        let padManager = PadManager(keychainService: keychain)
        let conversationId = "test-conversation"
        let padBytes: [UInt8] = Array(repeating: 0xAB, count: 1000)

        try await padManager.storePad(bytes: padBytes, for: conversationId)

        // Initial offset for responder is total size (end of pad)
        let offset1 = try await padManager.nextSendOffset(role: .responder, for: conversationId)
        #expect(offset1 == 1000)

        // After consuming 100 bytes, offset is 900 (moved backward)
        _ = try await padManager.consumeForSending(length: 100, role: .responder, for: conversationId)
        let offset2 = try await padManager.nextSendOffset(role: .responder, for: conversationId)
        #expect(offset2 == 900)
    }

    // MARK: - Peer Consumption Update

    @Test func updatePeerConsumption_updatesAvailableBytes() async throws {
        let keychain = MockKeychainService()
        let padManager = PadManager(keychainService: keychain)
        let conversationId = "test-conversation"
        let padBytes: [UInt8] = Array(repeating: 0xAB, count: 1000)

        try await padManager.storePad(bytes: padBytes, for: conversationId)

        // We are responder, peer (initiator) consumed 600 bytes
        try await padManager.updatePeerConsumption(peerRole: .initiator, consumed: 600, for: conversationId)

        // Now we can only send 400 bytes
        let available = try await padManager.availableForSending(role: .responder, for: conversationId)
        #expect(available == 400)

        let canSend400 = try await padManager.canSend(length: 400, role: .responder, for: conversationId)
        let canSend401 = try await padManager.canSend(length: 401, role: .responder, for: conversationId)
        #expect(canSend400 == true)
        #expect(canSend401 == false)
    }

    @Test func updatePeerConsumption_onlyIncreases() async throws {
        let keychain = MockKeychainService()
        let padManager = PadManager(keychainService: keychain)
        let conversationId = "test-conversation"
        let padBytes: [UInt8] = Array(repeating: 0xAB, count: 1000)

        try await padManager.storePad(bytes: padBytes, for: conversationId)

        // Peer consumed 500 bytes
        try await padManager.updatePeerConsumption(peerRole: .initiator, consumed: 500, for: conversationId)
        let state1 = try await padManager.getPadState(for: conversationId)
        #expect(state1.consumedFront == 500)

        // Try to set lower value (replay protection) - should be ignored
        try await padManager.updatePeerConsumption(peerRole: .initiator, consumed: 300, for: conversationId)
        let state2 = try await padManager.getPadState(for: conversationId)
        #expect(state2.consumedFront == 500) // Still 500, not 300
    }

    // MARK: - Decryption

    @Test func getBytesForDecryption_returnsCorrectSlice() async throws {
        let keychain = MockKeychainService()
        let padManager = PadManager(keychainService: keychain)
        let conversationId = "test-conversation"
        // Create pad with sequential bytes for easy verification
        let padBytes: [UInt8] = (0..<100).map { UInt8($0) }

        try await padManager.storePad(bytes: padBytes, for: conversationId)

        // Get bytes at offset 10, length 5
        let decryptBytes = try await padManager.getBytesForDecryption(offset: 10, length: 5, for: conversationId)

        #expect(decryptBytes.count == 5)
        #expect(decryptBytes == [10, 11, 12, 13, 14])
    }

    // MARK: - Wipe

    @Test func wipePad_removesFromKeychain() async throws {
        let keychain = MockKeychainService()
        let padManager = PadManager(keychainService: keychain)
        let conversationId = "test-conversation"
        let padBytes: [UInt8] = Array(repeating: 0xAB, count: 1000)

        try await padManager.storePad(bytes: padBytes, for: conversationId)

        // Verify it exists
        let data1 = try keychain.retrieve(for: "pad.\(conversationId)")
        #expect(data1 != nil)

        // Wipe it
        try await padManager.wipePad(for: conversationId)

        // Verify it's gone
        let data2 = try keychain.retrieve(for: "pad.\(conversationId)")
        #expect(data2 == nil)
    }

    @Test func wipeAllPads_removesAllFromKeychain() async throws {
        let keychain = MockKeychainService()
        let padManager = PadManager(keychainService: keychain)

        // Store multiple pads
        try await padManager.storePad(bytes: [1, 2, 3], for: "conv1")
        try await padManager.storePad(bytes: [4, 5, 6], for: "conv2")

        // Wipe all
        try await padManager.wipeAllPads()

        // Verify both are gone
        let data1 = try keychain.retrieve(for: "pad.conv1")
        let data2 = try keychain.retrieve(for: "pad.conv2")
        #expect(data1 == nil)
        #expect(data2 == nil)
    }

    // MARK: - State Persistence

    @Test func padState_persistsAcrossLoads() async throws {
        let keychain = MockKeychainService()
        let conversationId = "test-conversation"
        let padBytes: [UInt8] = Array(repeating: 0xAB, count: 1000)

        // First pad manager instance
        let padManager1 = PadManager(keychainService: keychain)
        try await padManager1.storePad(bytes: padBytes, for: conversationId)
        _ = try await padManager1.consumeForSending(length: 100, role: .initiator, for: conversationId)
        _ = try await padManager1.consumeForSending(length: 200, role: .responder, for: conversationId)

        // Second pad manager instance (simulates app restart)
        let padManager2 = PadManager(keychainService: keychain)
        let state = try await padManager2.getPadState(for: conversationId)

        // State should be preserved
        #expect(state.totalBytes == 1000)
        #expect(state.consumedFront == 100)
        #expect(state.consumedBack == 200)
        #expect(state.remaining == 700)
    }

    // MARK: - Available for Sending

    @Test func availableForSending_returnsRemainingBytes() async throws {
        let keychain = MockKeychainService()
        let padManager = PadManager(keychainService: keychain)
        let conversationId = "test-conversation"
        let padBytes: [UInt8] = Array(repeating: 0xAB, count: 1000)

        try await padManager.storePad(bytes: padBytes, for: conversationId)

        // Initially 1000 bytes available
        let available1 = try await padManager.availableForSending(role: .initiator, for: conversationId)
        #expect(available1 == 1000)

        // After initiator consumes 300
        _ = try await padManager.consumeForSending(length: 300, role: .initiator, for: conversationId)
        let available2 = try await padManager.availableForSending(role: .initiator, for: conversationId)
        #expect(available2 == 700)

        // After responder consumes 400
        _ = try await padManager.consumeForSending(length: 400, role: .responder, for: conversationId)
        let available3 = try await padManager.availableForSending(role: .initiator, for: conversationId)
        #expect(available3 == 300)
    }

    // MARK: - Bytes Don't Overlap

    @Test func consumeForSending_bytesNeverOverlap() async throws {
        let keychain = MockKeychainService()
        let padManager = PadManager(keychainService: keychain)
        let conversationId = "test-conversation"
        // Create pad with sequential bytes
        let padBytes: [UInt8] = (0..<100).map { UInt8($0) }

        try await padManager.storePad(bytes: padBytes, for: conversationId)

        // Alice takes 30 bytes from front
        let aliceBytes = try await padManager.consumeForSending(length: 30, role: .initiator, for: conversationId)

        // Bob takes 60 bytes from back
        let bobBytes = try await padManager.consumeForSending(length: 60, role: .responder, for: conversationId)

        // Verify no overlap
        let aliceSet = Set(aliceBytes)
        let bobSet = Set(bobBytes)
        let intersection = aliceSet.intersection(bobSet)

        #expect(intersection.isEmpty, "Alice and Bob bytes should never overlap")

        // Alice should have bytes 0-29
        #expect(aliceBytes == Array(0..<30).map { UInt8($0) })
        // Bob should have bytes 40-99 (from the end)
        #expect(bobBytes == Array(40..<100).map { UInt8($0) })
    }
}
