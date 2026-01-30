//
//  MockCryptoService.swift
//  AshTests
//
//  Mock implementation of CryptoServiceProtocol for testing
//

import Foundation
@testable import Ash

/// Mock crypto service for testing - uses simple XOR encryption
final class MockCryptoService: CryptoServiceProtocol, @unchecked Sendable {
    // MARK: - Call Tracking

    private(set) var encryptCalled = false
    private(set) var decryptCalled = false
    private(set) var lastEncryptKey: [UInt8]?
    private(set) var lastDecryptKey: [UInt8]?

    // MARK: - Error Simulation

    var encryptError: CryptoError?
    var decryptError: CryptoError?

    // MARK: - Protocol Implementation

    func encrypt(plaintext: [UInt8], key: [UInt8]) throws -> [UInt8] {
        encryptCalled = true
        lastEncryptKey = key

        if let error = encryptError {
            throw error
        }

        // Simple XOR encryption for testing
        guard plaintext.count == key.count else {
            throw CryptoError.keyLengthMismatch
        }

        return zip(plaintext, key).map { $0 ^ $1 }
    }

    func decrypt(ciphertext: [UInt8], key: [UInt8]) throws -> [UInt8] {
        decryptCalled = true
        lastDecryptKey = key

        if let error = decryptError {
            throw error
        }

        // Simple XOR decryption for testing (same as encrypt)
        guard ciphertext.count == key.count else {
            throw CryptoError.keyLengthMismatch
        }

        return zip(ciphertext, key).map { $0 ^ $1 }
    }

    func encryptAuthenticated(plaintext: [UInt8], authKey: [UInt8], encryptionKey: [UInt8], messageType: MessageType) throws -> [UInt8] {
        encryptCalled = true
        lastEncryptKey = encryptionKey

        if let error = encryptError {
            throw error
        }

        // Simple mock: XOR encrypt and append a fake 32-byte tag
        let ciphertext = zip(plaintext, encryptionKey).map { $0 ^ $1 }
        let fakeTag = [UInt8](repeating: 0xAB, count: 32)
        return [messageType.rawValue] + ciphertext + fakeTag
    }

    func decryptAuthenticated(encodedFrame: [UInt8], authKey: [UInt8], encryptionKey: [UInt8]) throws -> AuthenticatedDecryptResult {
        decryptCalled = true
        lastDecryptKey = encryptionKey

        if let error = decryptError {
            throw error
        }

        // Parse mock frame: [msgType (1)] + [ciphertext (N)] + [tag (32)]
        guard encodedFrame.count >= 33 else {
            throw CryptoError.invalidData
        }

        let msgType = MessageType(rawValue: encodedFrame[0]) ?? .text
        let ciphertext = Array(encodedFrame[1..<(encodedFrame.count - 32)])
        let tag = Array(encodedFrame.suffix(32))

        let plaintext = zip(ciphertext, encryptionKey).map { $0 ^ $1 }

        return AuthenticatedDecryptResult(plaintext: plaintext, messageType: msgType, authTag: tag)
    }

    func calculatePadConsumption(plaintextLength: Int) -> Int {
        // 64 bytes auth overhead + plaintext length
        return 64 + plaintextLength
    }

    func generateSecurePad(userEntropy: [UInt8], sizeBytes: Int) throws -> [UInt8] {
        // Return predictable bytes for testing (0, 1, 2, 3, ...)
        return (0..<sizeBytes).map { UInt8($0 % 256) }
    }

    func generateMnemonic(from padBytes: [UInt8], wordCount: Int) -> [String] {
        // Return predictable mnemonic for testing
        return Array(repeating: "test", count: wordCount)
    }

    // MARK: - Test Helpers

    func reset() {
        encryptCalled = false
        decryptCalled = false
        lastEncryptKey = nil
        lastDecryptKey = nil
        encryptError = nil
        decryptError = nil
    }
}
