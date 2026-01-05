//
//  PerformanceTests.swift
//  AshTests
//
//  Performance tests for crypto and pad operations
//

import Testing
import Foundation
@testable import Ash

struct PerformanceTests {

    // MARK: - PadKeychainData Encoding Performance

    @Test func padEncoding_64KB_completesQuickly() throws {
        let padBytes = [UInt8](repeating: 0xAB, count: 64 * 1024)
        let padData = PadKeychainData(bytes: padBytes, consumedOffset: 1000)

        let start = Date()
        let encoded = try padData.encode()
        let elapsed = Date().timeIntervalSince(start)

        print("64KB pad encoding: \(elapsed * 1000)ms, size: \(encoded.count) bytes")

        // Should complete in under 10ms
        #expect(elapsed < 0.01, "64KB encoding took \(elapsed * 1000)ms, expected < 10ms")
        // Binary encoding should be close to original size + 8 bytes
        #expect(encoded.count == padBytes.count + 8)
    }

    @Test func padEncoding_256KB_completesQuickly() throws {
        let padBytes = [UInt8](repeating: 0xCD, count: 256 * 1024)
        let padData = PadKeychainData(bytes: padBytes, consumedOffset: 5000)

        let start = Date()
        let encoded = try padData.encode()
        let elapsed = Date().timeIntervalSince(start)

        print("256KB pad encoding: \(elapsed * 1000)ms, size: \(encoded.count) bytes")

        // Should complete in under 50ms
        #expect(elapsed < 0.05, "256KB encoding took \(elapsed * 1000)ms, expected < 50ms")
        #expect(encoded.count == padBytes.count + 8)
    }

    @Test func padEncoding_1MB_completesQuickly() throws {
        let padBytes = [UInt8](repeating: 0xEF, count: 1024 * 1024)
        let padData = PadKeychainData(bytes: padBytes, consumedOffset: 10000)

        let start = Date()
        let encoded = try padData.encode()
        let elapsed = Date().timeIntervalSince(start)

        print("1MB pad encoding: \(elapsed * 1000)ms, size: \(encoded.count) bytes")

        // Should complete in under 100ms
        #expect(elapsed < 0.1, "1MB encoding took \(elapsed * 1000)ms, expected < 100ms")
        #expect(encoded.count == padBytes.count + 8)
    }

    // MARK: - PadKeychainData Decoding Performance

    @Test func padDecoding_64KB_completesQuickly() throws {
        let padBytes = [UInt8](repeating: 0xAB, count: 64 * 1024)
        let original = PadKeychainData(bytes: padBytes, consumedOffset: 1000)
        let encoded = try original.encode()

        let start = Date()
        let decoded = try PadKeychainData.decode(from: encoded)
        let elapsed = Date().timeIntervalSince(start)

        print("64KB pad decoding: \(elapsed * 1000)ms")

        // Should complete in under 10ms
        #expect(elapsed < 0.01, "64KB decoding took \(elapsed * 1000)ms, expected < 10ms")
        #expect(decoded.bytes.count == padBytes.count)
        #expect(decoded.consumedOffset == 1000)
    }

    @Test func padDecoding_1MB_completesQuickly() throws {
        let padBytes = [UInt8](repeating: 0xEF, count: 1024 * 1024)
        let original = PadKeychainData(bytes: padBytes, consumedOffset: 10000)
        let encoded = try original.encode()

        let start = Date()
        let decoded = try PadKeychainData.decode(from: encoded)
        let elapsed = Date().timeIntervalSince(start)

        print("1MB pad decoding: \(elapsed * 1000)ms")

        // Should complete in under 100ms
        #expect(elapsed < 0.1, "1MB decoding took \(elapsed * 1000)ms, expected < 100ms")
        #expect(decoded.bytes.count == padBytes.count)
        #expect(decoded.consumedOffset == 10000)
    }

    // MARK: - Round-trip Performance

    @Test func padRoundTrip_1MB_preservesData() throws {
        let padBytes = (0..<(1024 * 1024)).map { UInt8($0 & 0xFF) }
        let original = PadKeychainData(bytes: padBytes, consumedOffset: 123456)

        let encoded = try original.encode()
        let decoded = try PadKeychainData.decode(from: encoded)

        #expect(decoded.bytes == original.bytes)
        #expect(decoded.consumedOffset == original.consumedOffset)
    }

    // MARK: - Large Message Simulation

    @Test func largeMessage_32KB_encryptionSimulation() throws {
        // Simulate encrypting a 32KB message
        let messageBytes = [UInt8](repeating: 0x42, count: 32 * 1024)
        let keyBytes = [UInt8](repeating: 0xAB, count: 32 * 1024)

        let start = Date()
        // XOR encryption (what ash-core does)
        var ciphertext = [UInt8](repeating: 0, count: messageBytes.count)
        for i in 0..<messageBytes.count {
            ciphertext[i] = messageBytes[i] ^ keyBytes[i]
        }
        let elapsed = Date().timeIntervalSince(start)

        print("32KB XOR encryption: \(elapsed * 1000)ms")

        // Should complete in under 100ms (generous for CI/simulator overhead)
        #expect(elapsed < 0.1, "32KB XOR took \(elapsed * 1000)ms, expected < 100ms")
    }

    // MARK: - Array Slicing Performance

    @Test func arraySlicing_32KBfrom1MB_completesQuickly() throws {
        let padBytes = [UInt8](repeating: 0xCD, count: 1024 * 1024)

        let start = Date()
        // Simulate retrieving 32KB from middle of 1MB pad
        let offset = 500_000
        let length = 32 * 1024
        let slice = Array(padBytes[offset..<(offset + length)])
        let elapsed = Date().timeIntervalSince(start)

        print("32KB slice from 1MB: \(elapsed * 1000)ms")

        // Should complete in under 5ms
        #expect(elapsed < 0.005, "Slicing took \(elapsed * 1000)ms, expected < 5ms")
        #expect(slice.count == length)
    }
}

// MARK: - Binary Encoding Correctness Tests

struct PadKeychainDataTests {

    @Test func encode_preservesOffset() throws {
        let padData = PadKeychainData(bytes: [1, 2, 3, 4], consumedOffset: 0x123456789ABCDEF0)

        let encoded = try padData.encode()
        let decoded = try PadKeychainData.decode(from: encoded)

        #expect(decoded.consumedOffset == 0x123456789ABCDEF0)
    }

    @Test func encode_preservesBytes() throws {
        let bytes: [UInt8] = [0x00, 0xFF, 0x42, 0xAB, 0xCD, 0xEF]
        let padData = PadKeychainData(bytes: bytes, consumedOffset: 0)

        let encoded = try padData.encode()
        let decoded = try PadKeychainData.decode(from: encoded)

        #expect(decoded.bytes == bytes)
    }

    @Test func decode_tooShort_throws() {
        let shortData = Data([1, 2, 3]) // Less than 8 bytes

        #expect(throws: KeychainError.self) {
            _ = try PadKeychainData.decode(from: shortData)
        }
    }

    @Test func encode_emptyBytes_works() throws {
        let padData = PadKeychainData(bytes: [], consumedOffset: 42)

        let encoded = try padData.encode()
        let decoded = try PadKeychainData.decode(from: encoded)

        #expect(decoded.bytes.isEmpty)
        #expect(decoded.consumedOffset == 42)
    }

    @Test func binaryFormat_offsetIsLittleEndian() throws {
        let padData = PadKeychainData(bytes: [0xAB, 0xCD], consumedOffset: 0x0102030405060708)

        let encoded = try padData.encode()

        // First 8 bytes should be offset in little-endian
        // 0x0102030405060708 in little-endian is: 08 07 06 05 04 03 02 01
        #expect(encoded[0] == 0x08)
        #expect(encoded[1] == 0x07)
        #expect(encoded[2] == 0x06)
        #expect(encoded[3] == 0x05)
        #expect(encoded[4] == 0x04)
        #expect(encoded[5] == 0x03)
        #expect(encoded[6] == 0x02)
        #expect(encoded[7] == 0x01)

        // Remaining bytes are the pad
        #expect(encoded[8] == 0xAB)
        #expect(encoded[9] == 0xCD)
    }
}
