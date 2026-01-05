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

    func generateSecurePad(userEntropy: [UInt8], size: PadSize) throws -> [UInt8] {
        // Return predictable bytes for testing (0, 1, 2, 3, ...)
        let byteCount = Int(size.bytes)
        return (0..<byteCount).map { UInt8($0 % 256) }
    }

    func generateMnemonic(from padBytes: [UInt8], wordCount: Int) -> [String] {
        // Return predictable mnemonic for testing
        return Array(repeating: "test", count: wordCount)
    }

    func createFrames(from padBytes: [UInt8], maxPayload: UInt32) throws -> [Frame] {
        // Not needed for SendMessageUseCase tests
        return []
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
