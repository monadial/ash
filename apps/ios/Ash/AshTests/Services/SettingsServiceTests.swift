//
//  SettingsServiceTests.swift
//  AshTests
//
//  Unit tests for SettingsService
//

import Testing
import Foundation
@testable import Ash

struct SettingsServiceTests {

    // Use a unique suite name for test isolation
    private func createTestUserDefaults() -> UserDefaults {
        let suiteName = "com.ash.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test func isBiometricLockEnabled_defaultsFalse() {
        let defaults = createTestUserDefaults()
        let service = SettingsService(defaults: defaults)

        #expect(service.isBiometricLockEnabled == false)
    }

    @Test func isBiometricLockEnabled_persistsValue() {
        let defaults = createTestUserDefaults()
        let service = SettingsService(defaults: defaults)

        service.isBiometricLockEnabled = true
        #expect(service.isBiometricLockEnabled == true)

        service.isBiometricLockEnabled = false
        #expect(service.isBiometricLockEnabled == false)
    }

    @Test func lockOnBackground_defaultsTrue() {
        let defaults = createTestUserDefaults()
        let service = SettingsService(defaults: defaults)

        #expect(service.lockOnBackground == true)
    }

    @Test func lockOnBackground_persistsValue() {
        let defaults = createTestUserDefaults()
        let service = SettingsService(defaults: defaults)

        service.lockOnBackground = false
        #expect(service.lockOnBackground == false)

        service.lockOnBackground = true
        #expect(service.lockOnBackground == true)
    }

    @Test func settings_persistAcrossInstances() {
        let defaults = createTestUserDefaults()

        // Set values with first instance
        let service1 = SettingsService(defaults: defaults)
        service1.isBiometricLockEnabled = true
        service1.lockOnBackground = false

        // Read with second instance
        let service2 = SettingsService(defaults: defaults)
        #expect(service2.isBiometricLockEnabled == true)
        #expect(service2.lockOnBackground == false)
    }
}

// MARK: - MockSettingsService Tests

struct MockSettingsServiceTests {

    @Test func defaultValues() {
        let service = MockSettingsService()

        #expect(service.isBiometricLockEnabled == false)
        #expect(service.lockOnBackground == true)
    }

    @Test func setValues() {
        let service = MockSettingsService()

        service.isBiometricLockEnabled = true
        service.lockOnBackground = false

        #expect(service.isBiometricLockEnabled == true)
        #expect(service.lockOnBackground == false)
    }

    @Test func reset_restoresDefaults() {
        let service = MockSettingsService()
        service.isBiometricLockEnabled = true
        service.lockOnBackground = false

        service.reset()

        #expect(service.isBiometricLockEnabled == false)
        #expect(service.lockOnBackground == true)
    }
}
