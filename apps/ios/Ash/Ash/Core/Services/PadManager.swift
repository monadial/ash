//
//  PadManager.swift
//  Ash
//
//  Core Service - Manages pad state using Rust core for allocation logic
//
//  This service wraps the Rust Pad implementation to ensure iOS and Android
//  use identical pad allocation logic. All pad operations go through this service.
//

import Foundation

// MARK: - Sendable Conformance for FFI Types

// Role enum from UniFFI is safe to send across concurrency boundaries
extension Role: @unchecked Sendable {}

/// Errors that can occur during pad operations
enum PadManagerError: Error, Sendable {
    case padNotFound
    case insufficientBytes
    case storageError(Error)
    case invalidState
}

/// Protocol for pad management operations
/// Note: loadPad is not in protocol as Pad is non-Sendable (implementation detail)
protocol PadManagerProtocol: Sendable {
    /// Store pad bytes with initial state (after ceremony)
    func storePad(bytes: [UInt8], for conversationId: String) async throws

    /// Check if a message of given length can be sent
    func canSend(length: UInt32, role: Role, for conversationId: String) async throws -> Bool

    /// Get bytes available for sending
    func availableForSending(role: Role, for conversationId: String) async throws -> UInt64

    /// Consume pad bytes for sending a message
    /// Returns the key bytes for encryption
    func consumeForSending(length: UInt32, role: Role, for conversationId: String) async throws -> [UInt8]

    /// Get the next send offset (for message sequencing)
    func nextSendOffset(role: Role, for conversationId: String) async throws -> UInt64

    /// Update peer's consumption based on received message
    func updatePeerConsumption(peerRole: Role, consumed: UInt64, for conversationId: String) async throws

    /// Get pad bytes for decryption at a specific offset
    func getBytesForDecryption(offset: UInt64, length: UInt64, for conversationId: String) async throws -> [UInt8]

    /// Get current pad state (for UI display)
    func getPadState(for conversationId: String) async throws -> PadState

    /// Zero pad bytes at specific offset (for forward secrecy)
    /// When a message expires, the key material is zeroed to prevent future decryption
    func zeroPadBytes(offset: UInt64, length: UInt64, for conversationId: String) async throws

    /// Wipe pad for a conversation
    func wipePad(for conversationId: String) async throws

    /// Wipe all pads
    func wipeAllPads() async throws

    /// Get pad bytes for token derivation (auth/burn tokens)
    /// Must be called BEFORE wiping the pad
    func getPadBytes(for conversationId: String) async throws -> [UInt8]
}

/// Represents the current state of a pad
struct PadState: Sendable {
    let totalBytes: UInt64
    let consumedFront: UInt64
    let consumedBack: UInt64
    let remaining: UInt64
    let isExhausted: Bool
}

/// Data stored in Keychain for a pad
struct PadStorageData: Codable {
    let bytes: [UInt8]
    let consumedFront: UInt64
    let consumedBack: UInt64

    func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(from data: Data) throws -> PadStorageData {
        try JSONDecoder().decode(PadStorageData.self, from: data)
    }
}

/// Actor managing pad state using Rust core
actor PadManager: PadManagerProtocol {
    private let keychainService: KeychainServiceProtocol

    /// In-memory cache of loaded pads
    private var padCache: [String: Pad] = [:]

    init(keychainService: KeychainServiceProtocol = KeychainService()) {
        self.keychainService = keychainService
    }

    // MARK: - Load/Store

    func loadPad(for conversationId: String) async throws -> Pad {
        // Check cache first
        if let cached = padCache[conversationId] {
            return cached
        }

        // Load from Keychain
        guard let data = try keychainService.retrieve(for: keychainKey(for: conversationId)) else {
            throw PadManagerError.padNotFound
        }

        let storageData = try PadStorageData.decode(from: data)

        // Create Rust Pad with state
        let pad = Pad.fromBytesWithState(
            bytes: storageData.bytes,
            consumedFront: storageData.consumedFront,
            consumedBack: storageData.consumedBack
        )

        padCache[conversationId] = pad
        return pad
    }

    func storePad(bytes: [UInt8], for conversationId: String) async throws {
        let storageData = PadStorageData(
            bytes: bytes,
            consumedFront: 0,
            consumedBack: 0
        )

        let encoded = try storageData.encode()
        try keychainService.store(data: encoded, for: keychainKey(for: conversationId))

        // Create and cache the Rust Pad
        let pad = Pad.fromBytes(bytes: bytes)
        padCache[conversationId] = pad
    }

    private func savePadState(pad: Pad, for conversationId: String) throws {
        let storageData = PadStorageData(
            bytes: pad.asBytes(),
            consumedFront: pad.consumedFront(),
            consumedBack: pad.consumedBack()
        )

        let encoded = try storageData.encode()
        try keychainService.store(data: encoded, for: keychainKey(for: conversationId))
    }

    // MARK: - Send Operations

    func canSend(length: UInt32, role: Role, for conversationId: String) async throws -> Bool {
        let pad = try await loadPad(for: conversationId)
        return pad.canSend(length: length, role: role)
    }

    func availableForSending(role: Role, for conversationId: String) async throws -> UInt64 {
        let pad = try await loadPad(for: conversationId)
        return pad.availableForSending(role: role)
    }

    func consumeForSending(length: UInt32, role: Role, for conversationId: String) async throws -> [UInt8] {
        let pad = try await loadPad(for: conversationId)

        // Consume bytes using Rust Pad
        let keyBytes = try pad.consume(n: length, role: role)

        // Persist updated state
        try savePadState(pad: pad, for: conversationId)

        return keyBytes
    }

    func nextSendOffset(role: Role, for conversationId: String) async throws -> UInt64 {
        let pad = try await loadPad(for: conversationId)
        return pad.nextSendOffset(role: role)
    }

    // MARK: - Receive Operations

    func updatePeerConsumption(peerRole: Role, consumed: UInt64, for conversationId: String) async throws {
        let pad = try await loadPad(for: conversationId)
        pad.updatePeerConsumption(peerRole: peerRole, newConsumed: consumed)

        // Persist updated state
        try savePadState(pad: pad, for: conversationId)
    }

    func getBytesForDecryption(offset: UInt64, length: UInt64, for conversationId: String) async throws -> [UInt8] {
        let pad = try await loadPad(for: conversationId)
        let bytes = pad.asBytes()

        let start = Int(offset)
        let end = min(start + Int(length), bytes.count)

        guard start >= 0, end <= bytes.count, start < end else {
            throw PadManagerError.insufficientBytes
        }

        return Array(bytes[start..<end])
    }

    // MARK: - State Queries

    func getPadState(for conversationId: String) async throws -> PadState {
        let pad = try await loadPad(for: conversationId)
        return PadState(
            totalBytes: pad.totalSize(),
            consumedFront: pad.consumedFront(),
            consumedBack: pad.consumedBack(),
            remaining: pad.remaining(),
            isExhausted: pad.isExhausted()
        )
    }

    // MARK: - Forward Secrecy

    func zeroPadBytes(offset: UInt64, length: UInt64, for conversationId: String) async throws {
        let pad = try await loadPad(for: conversationId)

        // Zero the bytes using Rust's secure zeroing
        let success = pad.zeroBytesAt(offset: offset, length: length)

        if success {
            // Persist updated state (with zeroed bytes)
            try savePadState(pad: pad, for: conversationId)
            Log.debug(.crypto, "Zeroed \(length) pad bytes at offset \(offset) for forward secrecy")
        } else {
            Log.warning(.crypto, "Failed to zero pad bytes: offset \(offset), length \(length) out of bounds")
        }
    }

    // MARK: - Cleanup

    func wipePad(for conversationId: String) async throws {
        try keychainService.delete(for: keychainKey(for: conversationId))
        padCache.removeValue(forKey: conversationId)
    }

    func wipeAllPads() async throws {
        // Delete all pad keys from keychain
        // Note: This assumes we can identify pad keys by prefix
        try keychainService.deleteAll()
        padCache.removeAll()
    }

    func getPadBytes(for conversationId: String) async throws -> [UInt8] {
        let pad = try await loadPad(for: conversationId)
        return pad.asBytes()
    }

    // MARK: - Helpers

    private func keychainKey(for conversationId: String) -> String {
        "pad.\(conversationId)"
    }
}
