//
//  CryptoService.swift
//  Ash
//
//  Core cryptographic operations using ash-core FFI
//

import Foundation
import Security

protocol CryptoServiceProtocol: Sendable {
    func encrypt(plaintext: [UInt8], key: [UInt8]) throws -> [UInt8]
    func decrypt(ciphertext: [UInt8], key: [UInt8]) throws -> [UInt8]
    func generateSecurePad(userEntropy: [UInt8], size: PadSize) throws -> [UInt8]
    func generateMnemonic(from padBytes: [UInt8], wordCount: Int) -> [String]
}

enum CryptoError: Error, Sendable {
    case keyLengthMismatch
    case invalidData
    case entropyInsufficient
    case randomGenerationFailed
    case ffiError(String)
}

final class CryptoService: CryptoServiceProtocol, Sendable {

    func encrypt(plaintext: [UInt8], key: [UInt8]) throws -> [UInt8] {
        do {
            return try Ash.encrypt(key: key, plaintext: plaintext)
        } catch let error as AshError {
            throw CryptoError.ffiError(error.localizedDescription)
        }
    }

    func decrypt(ciphertext: [UInt8], key: [UInt8]) throws -> [UInt8] {
        do {
            return try Ash.decrypt(key: key, ciphertext: ciphertext)
        } catch let error as AshError {
            throw CryptoError.ffiError(error.localizedDescription)
        }
    }

    func generateSecurePad(userEntropy: [UInt8], size: PadSize) throws -> [UInt8] {
        let byteCount = Int(size.bytes)

        var randomBytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &randomBytes)

        guard status == errSecSuccess else {
            Log.error(.crypto, "SecRandomCopyBytes failed: \(status)")
            throw CryptoError.randomGenerationFailed
        }

        if !userEntropy.isEmpty {
            for i in 0..<byteCount {
                randomBytes[i] ^= userEntropy[i % userEntropy.count]
            }
        }

        Log.debug(.crypto, "Generated \(byteCount) byte pad with \(userEntropy.count) entropy bytes")
        return randomBytes
    }

    func generateMnemonic(from padBytes: [UInt8], wordCount: Int) -> [String] {
        if wordCount == 6 {
            return Ash.generateMnemonic(padBytes: padBytes)
        } else {
            return Ash.generateMnemonicWithCount(padBytes: padBytes, wordCount: UInt32(wordCount))
        }
    }
}

/// Namespace for ash-core FFI functions
/// Wraps global functions to avoid naming conflicts
private enum Ash {
    static func encrypt(key: [UInt8], plaintext: [UInt8]) throws -> [UInt8] {
        try _encrypt(key: key, plaintext: plaintext)
    }

    static func decrypt(key: [UInt8], ciphertext: [UInt8]) throws -> [UInt8] {
        try _decrypt(key: key, ciphertext: ciphertext)
    }

    static func generateMnemonic(padBytes: [UInt8]) -> [String] {
        _generateMnemonic(padBytes: padBytes)
    }

    static func generateMnemonicWithCount(padBytes: [UInt8], wordCount: UInt32) -> [String] {
        _generateMnemonicWithCount(padBytes: padBytes, wordCount: wordCount)
    }
}

// Private wrappers to call global FFI functions
private func _encrypt(key: [UInt8], plaintext: [UInt8]) throws -> [UInt8] {
    try encrypt(key: key, plaintext: plaintext)
}

private func _decrypt(key: [UInt8], ciphertext: [UInt8]) throws -> [UInt8] {
    try decrypt(key: key, ciphertext: ciphertext)
}

private func _generateMnemonic(padBytes: [UInt8]) -> [String] {
    generateMnemonic(padBytes: padBytes)
}

private func _generateMnemonicWithCount(padBytes: [UInt8], wordCount: UInt32) -> [String] {
    generateMnemonicWithCount(padBytes: padBytes, wordCount: wordCount)
}
