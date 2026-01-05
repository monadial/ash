//
//  MockKeychainService.swift
//  AshTests
//
//  Mock implementation of KeychainServiceProtocol for testing
//

import Foundation
@testable import Ash

/// Mock keychain service for testing (in-memory storage)
final class MockKeychainService: KeychainServiceProtocol, @unchecked Sendable {
    // MARK: - Storage

    private var storage: [String: Data] = [:]

    // MARK: - Call Tracking

    private(set) var storeCalled = false
    private(set) var retrieveCalled = false
    private(set) var deleteCalled = false
    private(set) var deleteAllCalled = false
    private(set) var existsCalled = false
    private(set) var allKeysCalled = false

    // MARK: - Error Simulation

    var storeError: KeychainError?
    var retrieveError: KeychainError?
    var deleteError: KeychainError?

    // MARK: - Protocol Implementation

    func store(data: Data, for key: String) throws {
        storeCalled = true
        if let error = storeError {
            throw error
        }
        storage[key] = data
    }

    func retrieve(for key: String) throws -> Data? {
        retrieveCalled = true
        if let error = retrieveError {
            throw error
        }
        return storage[key]
    }

    func delete(for key: String) throws {
        deleteCalled = true
        if let error = deleteError {
            throw error
        }
        storage.removeValue(forKey: key)
    }

    func deleteAll() throws {
        deleteAllCalled = true
        storage.removeAll()
    }

    func exists(for key: String) throws -> Bool {
        existsCalled = true
        return storage[key] != nil
    }

    func allKeys(withPrefix prefix: String) throws -> [String] {
        allKeysCalled = true
        return storage.keys.filter { $0.hasPrefix(prefix) }
    }

    // MARK: - Test Helpers

    var storedKeys: [String] {
        Array(storage.keys)
    }

    var storedData: [String: Data] {
        storage
    }

    func reset() {
        storage.removeAll()
        storeCalled = false
        retrieveCalled = false
        deleteCalled = false
        deleteAllCalled = false
        existsCalled = false
        allKeysCalled = false
        storeError = nil
        retrieveError = nil
        deleteError = nil
    }
}
