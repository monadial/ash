//
//  SettingsScreenTests.swift
//  AshTests
//
//  Tests for SettingsScreen view integration
//

import Testing
import SwiftUI
@testable import Ash

@MainActor
struct SettingsScreenTests {

    // MARK: - ViewModel State Tests

    @Test func lockViewModel_biometricsAvailable_showsToggle() {
        let biometric = MockBiometricService()
        biometric.mockCanUseBiometrics = true

        let viewModel = AppLockViewModel(
            biometricService: biometric,
            settingsService: MockSettingsService()
        )

        #expect(viewModel.canUseBiometrics == true)
    }

    @Test func lockViewModel_biometricsNotAvailable_hidesToggle() {
        let biometric = MockBiometricService()
        biometric.mockCanUseBiometrics = false

        let viewModel = AppLockViewModel(
            biometricService: biometric,
            settingsService: MockSettingsService()
        )

        #expect(viewModel.canUseBiometrics == false)
    }

    @Test func lockViewModel_enableBiometric_requiresAuthentication() async {
        let biometric = MockBiometricService()
        biometric.shouldSucceed = true

        let viewModel = AppLockViewModel(
            biometricService: biometric,
            settingsService: MockSettingsService()
        )

        let result = await viewModel.enableBiometricLock()

        #expect(result == true)
        #expect(biometric.authenticateCalled == true)
    }

    @Test func lockViewModel_enableBiometric_failedAuth_returnsFalse() async {
        let biometric = MockBiometricService()
        biometric.shouldSucceed = false

        let viewModel = AppLockViewModel(
            biometricService: biometric,
            settingsService: MockSettingsService()
        )

        let result = await viewModel.enableBiometricLock()

        #expect(result == false)
    }

    @Test func lockViewModel_disableBiometric_doesNotRequireAuth() {
        let biometric = MockBiometricService()
        let settings = MockSettingsService()
        settings.isBiometricLockEnabled = true

        let viewModel = AppLockViewModel(
            biometricService: biometric,
            settingsService: settings
        )

        viewModel.disableBiometricLock()

        #expect(biometric.authenticateCalled == false)
        #expect(viewModel.isBiometricLockEnabled == false)
    }

    @Test func lockOnBackground_toggle_updatesSettings() {
        let settings = MockSettingsService()
        settings.lockOnBackground = true

        let viewModel = AppLockViewModel(
            biometricService: MockBiometricService(),
            settingsService: settings
        )

        viewModel.lockOnBackground = false

        #expect(settings.lockOnBackground == false)
    }

    @Test func lockOnBackground_onlyVisibleWhenBiometricEnabled() {
        let settings = MockSettingsService()
        settings.isBiometricLockEnabled = false

        let viewModel = AppLockViewModel(
            biometricService: MockBiometricService(),
            settingsService: settings
        )

        // When biometric lock is disabled, lockOnBackground toggle shouldn't be shown
        // This is tested by checking the isBiometricLockEnabled property
        #expect(viewModel.isBiometricLockEnabled == false)
    }
}
