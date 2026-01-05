//
//  LockScreenTests.swift
//  AshTests
//
//  Tests for LockScreen view and its integration with AppLockViewModel
//

import Testing
import SwiftUI
@testable import Ash

@MainActor
struct LockScreenTests {

    // MARK: - ViewModel Integration Tests

    @Test func viewModel_showsCorrectBiometricType() {
        let biometric = MockBiometricService()
        biometric.mockBiometricType = .faceID

        let viewModel = AppLockViewModel(
            biometricService: biometric,
            settingsService: MockSettingsService()
        )

        #expect(viewModel.biometricType == .faceID)
        #expect(viewModel.biometricType.displayName == "Face ID")
        #expect(viewModel.biometricType.iconName == "faceid")
    }

    @Test func viewModel_touchID_showsCorrectInfo() {
        let biometric = MockBiometricService()
        biometric.mockBiometricType = .touchID

        let viewModel = AppLockViewModel(
            biometricService: biometric,
            settingsService: MockSettingsService()
        )

        #expect(viewModel.biometricType == .touchID)
        #expect(viewModel.biometricType.displayName == "Touch ID")
        #expect(viewModel.biometricType.iconName == "touchid")
    }

    @Test func viewModel_isAuthenticating_startsAsFalse() {
        let settings = MockSettingsService()
        settings.isBiometricLockEnabled = true

        let viewModel = AppLockViewModel(
            biometricService: MockBiometricService(),
            settingsService: settings
        )

        #expect(viewModel.isAuthenticating == false)
    }

    @Test func viewModel_authenticationError_startsAsNil() {
        let settings = MockSettingsService()
        settings.isBiometricLockEnabled = true

        let viewModel = AppLockViewModel(
            biometricService: MockBiometricService(),
            settingsService: settings
        )

        #expect(viewModel.authenticationError == nil)
    }

    @Test func unlock_setsIsAuthenticatingDuringProcess() async {
        let settings = MockSettingsService()
        settings.isBiometricLockEnabled = true

        let biometric = MockBiometricService()
        biometric.shouldSucceed = true

        let viewModel = AppLockViewModel(
            biometricService: biometric,
            settingsService: settings
        )

        // After unlock completes, isAuthenticating should be false
        await viewModel.unlock()

        #expect(viewModel.isAuthenticating == false)
    }
}
