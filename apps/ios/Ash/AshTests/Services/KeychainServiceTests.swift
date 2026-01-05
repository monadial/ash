//
//  KeychainServiceTests.swift
//  AshTests
//
//  Unit tests for KeychainService and MockKeychainService
//

import Testing
import Foundation
@testable import Ash

// MARK: - KeychainError Tests

struct KeychainErrorTests {

    @Test func storeFailed_containsStatus() {
        let error = KeychainError.storeFailed(-25300)
        if case .storeFailed(let status) = error {
            #expect(status == -25300)
        } else {
            Issue.record("Expected storeFailed case")
        }
    }

    @Test func retrieveFailed_containsStatus() {
        let error = KeychainError.retrieveFailed(-25300)
        if case .retrieveFailed(let status) = error {
            #expect(status == -25300)
        } else {
            Issue.record("Expected retrieveFailed case")
        }
    }

    @Test func deleteFailed_containsStatus() {
        let error = KeychainError.deleteFailed(-25300)
        if case .deleteFailed(let status) = error {
            #expect(status == -25300)
        } else {
            Issue.record("Expected deleteFailed case")
        }
    }
}

// MARK: - MockKeychainService Tests

struct MockKeychainServiceTests {

    @Test func store_savesData() throws {
        let service = MockKeychainService()
        let data = "test data".data(using: .utf8)!

        try service.store(data: data, for: "testKey")

        #expect(service.storeCalled == true)
        #expect(service.storedKeys.contains("testKey"))
    }

    @Test func store_withError_throwsError() {
        let service = MockKeychainService()
        service.storeError = .storeFailed(-25300)

        #expect(throws: KeychainError.self) {
            try service.store(data: Data(), for: "key")
        }
    }

    @Test func retrieve_returnsStoredData() throws {
        let service = MockKeychainService()
        let originalData = "test data".data(using: .utf8)!
        try service.store(data: originalData, for: "testKey")

        let retrievedData = try service.retrieve(for: "testKey")

        #expect(service.retrieveCalled == true)
        #expect(retrievedData == originalData)
    }

    @Test func retrieve_nonExistentKey_returnsNil() throws {
        let service = MockKeychainService()

        let data = try service.retrieve(for: "nonExistent")

        #expect(data == nil)
    }

    @Test func retrieve_withError_throwsError() {
        let service = MockKeychainService()
        service.retrieveError = .retrieveFailed(-25300)

        #expect(throws: KeychainError.self) {
            try service.retrieve(for: "key")
        }
    }

    @Test func delete_removesData() throws {
        let service = MockKeychainService()
        try service.store(data: Data(), for: "testKey")

        try service.delete(for: "testKey")

        #expect(service.deleteCalled == true)
        let data = try service.retrieve(for: "testKey")
        #expect(data == nil)
    }

    @Test func delete_withError_throwsError() {
        let service = MockKeychainService()
        service.deleteError = .deleteFailed(-25300)

        #expect(throws: KeychainError.self) {
            try service.delete(for: "key")
        }
    }

    @Test func deleteAll_removesAllData() throws {
        let service = MockKeychainService()
        try service.store(data: Data(), for: "key1")
        try service.store(data: Data(), for: "key2")

        try service.deleteAll()

        #expect(service.deleteAllCalled == true)
        #expect(service.storedKeys.isEmpty)
    }

    @Test func exists_returnsTrueForExistingKey() throws {
        let service = MockKeychainService()
        try service.store(data: Data(), for: "testKey")

        let exists = try service.exists(for: "testKey")

        #expect(service.existsCalled == true)
        #expect(exists == true)
    }

    @Test func exists_returnsFalseForNonExistentKey() throws {
        let service = MockKeychainService()

        let exists = try service.exists(for: "nonExistent")

        #expect(exists == false)
    }

    @Test func allKeys_withPrefix_returnsMatchingKeys() throws {
        let service = MockKeychainService()
        try service.store(data: Data(), for: "prefix.key1")
        try service.store(data: Data(), for: "prefix.key2")
        try service.store(data: Data(), for: "other.key3")

        let keys = try service.allKeys(withPrefix: "prefix.")

        #expect(service.allKeysCalled == true)
        #expect(keys.count == 2)
        #expect(keys.contains("prefix.key1"))
        #expect(keys.contains("prefix.key2"))
        #expect(!keys.contains("other.key3"))
    }

    @Test func reset_clearsAllState() throws {
        let service = MockKeychainService()
        try service.store(data: Data(), for: "key")
        _ = try service.retrieve(for: "key")
        try service.delete(for: "key")

        service.reset()

        #expect(service.storeCalled == false)
        #expect(service.retrieveCalled == false)
        #expect(service.deleteCalled == false)
        #expect(service.storedKeys.isEmpty)
    }
}

// NOTE: PadKeychainData tests moved to PerformanceTests.swift for comprehensive coverage
