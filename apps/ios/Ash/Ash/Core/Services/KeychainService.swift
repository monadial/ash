//
//  KeychainService.swift
//  Ash
//

import Foundation
import Security

protocol KeychainServiceProtocol: Sendable {
    func store(data: Data, for key: String) throws
    func retrieve(for key: String) throws -> Data?
    func delete(for key: String) throws
    func deleteAll() throws
    func exists(for key: String) throws -> Bool
    func allKeys(withPrefix prefix: String) throws -> [String]
}

enum KeychainError: Error, Sendable {
    case storeFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case encodingFailed
    case decodingFailed
    case unexpectedData
}

final class KeychainService: KeychainServiceProtocol, Sendable {
    private let service: String
    private let accessGroup: String?

    init(service: String = "com.monadial.ash.pads", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    func store(data: Data, for key: String) throws {
        try? delete(for: key)

        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }

    func retrieve(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.unexpectedData
            }
            return data

        case errSecItemNotFound:
            return nil

        default:
            throw KeychainError.retrieveFailed(status)
        }
    }

    func delete(for key: String) throws {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    func deleteAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    func exists(for key: String) throws -> Bool {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = false

        let status = SecItemCopyMatching(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw KeychainError.retrieveFailed(status)
        }
    }

    func allKeys(withPrefix prefix: String) throws -> [String] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let items = result as? [[String: Any]] else {
                return []
            }

            return items.compactMap { item in
                guard let key = item[kSecAttrAccount as String] as? String,
                      key.hasPrefix(prefix) else {
                    return nil
                }
                return key
            }

        case errSecItemNotFound:
            return []

        default:
            throw KeychainError.retrieveFailed(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}

/// Binary format: [8 bytes consumedOffset LE][pad bytes]
struct PadKeychainData {
    let bytes: [UInt8]
    var consumedOffset: UInt64

    init(bytes: [UInt8], consumedOffset: UInt64 = 0) {
        self.bytes = bytes
        self.consumedOffset = consumedOffset
    }

    func encode() throws -> Data {
        var data = Data()
        var offset = consumedOffset.littleEndian
        withUnsafeBytes(of: &offset) { data.append(contentsOf: $0) }
        data.append(contentsOf: bytes)
        return data
    }

    static func decode(from data: Data) throws -> PadKeychainData {
        guard data.count >= 8 else {
            throw KeychainError.decodingFailed
        }

        let offsetData = data.prefix(8)
        let consumedOffset = offsetData.withUnsafeBytes { ptr in
            ptr.loadUnaligned(as: UInt64.self).littleEndian
        }

        let bytes = Array(data.dropFirst(8))
        return PadKeychainData(bytes: bytes, consumedOffset: consumedOffset)
    }
}
