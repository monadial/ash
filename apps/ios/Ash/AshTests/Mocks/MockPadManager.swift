//
//  MockPadManager.swift
//  AshTests
//
//  Mock implementation of PadManagerProtocol for testing
//

import Foundation
@testable import Ash

/// Mock pad manager for testing that uses in-memory storage
actor MockPadManager: PadManagerProtocol {
    // MARK: - Storage

    private var pads: [String: MockPadState] = [:]

    // MARK: - Call Tracking

    private(set) var storePadCalled = false
    private(set) var canSendCalled = false
    private(set) var consumeForSendingCalled = false
    private(set) var nextSendOffsetCalled = false
    private(set) var getPadStateCalled = false

    // MARK: - Internal State

    private struct MockPadState {
        var bytes: [UInt8]
        var consumedFront: UInt64
        var consumedBack: UInt64

        var totalBytes: UInt64 { UInt64(bytes.count) }
        var remaining: UInt64 {
            let consumed = consumedFront + consumedBack
            return consumed < totalBytes ? totalBytes - consumed : 0
        }
    }

    // MARK: - Protocol Implementation

    func storePad(bytes: [UInt8], for conversationId: String) async throws {
        storePadCalled = true
        pads[conversationId] = MockPadState(
            bytes: bytes,
            consumedFront: 0,
            consumedBack: 0
        )
    }

    func canSend(length: UInt32, role: Role, for conversationId: String) async throws -> Bool {
        canSendCalled = true
        guard let pad = pads[conversationId] else { return false }
        return UInt64(length) <= pad.remaining
    }

    func availableForSending(role: Role, for conversationId: String) async throws -> UInt64 {
        guard let pad = pads[conversationId] else { return 0 }
        return pad.remaining
    }

    func consumeForSending(length: UInt32, role: Role, for conversationId: String) async throws -> [UInt8] {
        consumeForSendingCalled = true
        guard var pad = pads[conversationId] else {
            throw PadManagerError.padNotFound
        }

        let len = UInt64(length)
        guard len <= pad.remaining else {
            throw PadManagerError.insufficientBytes
        }

        let keyBytes: [UInt8]
        switch role {
        case .initiator:
            let start = Int(pad.consumedFront)
            let end = start + Int(length)
            keyBytes = Array(pad.bytes[start..<end])
            pad.consumedFront += len
        case .responder:
            let end = Int(pad.totalBytes - pad.consumedBack)
            let start = end - Int(length)
            keyBytes = Array(pad.bytes[start..<end])
            pad.consumedBack += len
        }

        pads[conversationId] = pad
        return keyBytes
    }

    func nextSendOffset(role: Role, for conversationId: String) async throws -> UInt64 {
        nextSendOffsetCalled = true
        guard let pad = pads[conversationId] else {
            throw PadManagerError.padNotFound
        }

        switch role {
        case .initiator:
            return pad.consumedFront
        case .responder:
            return pad.totalBytes - pad.consumedBack
        }
    }

    func updatePeerConsumption(peerRole: Role, consumed: UInt64, for conversationId: String) async throws {
        guard var pad = pads[conversationId] else { return }

        switch peerRole {
        case .initiator:
            if consumed > pad.consumedFront {
                pad.consumedFront = consumed
            }
        case .responder:
            if consumed > pad.consumedBack {
                pad.consumedBack = consumed
            }
        }

        pads[conversationId] = pad
    }

    func getBytesForDecryption(offset: UInt64, length: UInt64, for conversationId: String) async throws -> [UInt8] {
        guard let pad = pads[conversationId] else {
            throw PadManagerError.padNotFound
        }

        let start = Int(offset)
        let end = start + Int(length)

        guard start >= 0, end <= pad.bytes.count else {
            throw PadManagerError.insufficientBytes
        }

        return Array(pad.bytes[start..<end])
    }

    func getPadState(for conversationId: String) async throws -> PadState {
        getPadStateCalled = true
        guard let pad = pads[conversationId] else {
            throw PadManagerError.padNotFound
        }

        return PadState(
            totalBytes: pad.totalBytes,
            consumedFront: pad.consumedFront,
            consumedBack: pad.consumedBack,
            remaining: pad.remaining,
            isExhausted: pad.remaining == 0
        )
    }

    func wipePad(for conversationId: String) async throws {
        pads.removeValue(forKey: conversationId)
    }

    func wipeAllPads() async throws {
        pads.removeAll()
    }

    func getPadBytes(for conversationId: String) async throws -> [UInt8] {
        guard let pad = pads[conversationId] else {
            throw PadManagerError.padNotFound
        }
        return pad.bytes
    }

    // MARK: - Test Helpers

    func reset() {
        pads.removeAll()
        storePadCalled = false
        canSendCalled = false
        consumeForSendingCalled = false
        nextSendOffsetCalled = false
        getPadStateCalled = false
    }

    /// Get the current internal state for verification
    func getInternalState(for conversationId: String) async -> (consumedFront: UInt64, consumedBack: UInt64)? {
        guard let pad = pads[conversationId] else { return nil }
        return (pad.consumedFront, pad.consumedBack)
    }
}
