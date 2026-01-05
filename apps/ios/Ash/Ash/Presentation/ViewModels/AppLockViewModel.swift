//
//  AppLockViewModel.swift
//  Ash
//
//  Presentation Layer - App lock state management
//

import SwiftUI

/// View model managing app lock state with biometric authentication
@MainActor
@Observable
final class AppLockViewModel {
    // MARK: - Dependencies

    private let biometricService: BiometricServiceProtocol
    private let settingsService: SettingsServiceProtocol

    // MARK: - State

    private(set) var isLocked: Bool = false
    private(set) var isAuthenticating: Bool = false
    private(set) var authenticationError: String?

    // MARK: - Computed Properties

    var biometricType: BiometricType {
        biometricService.availableBiometricType
    }

    var canUseBiometrics: Bool {
        biometricService.canUseBiometrics
    }

    var isBiometricLockEnabled: Bool {
        get { settingsService.isBiometricLockEnabled }
        set {
            var settings = settingsService
            settings.isBiometricLockEnabled = newValue
            if newValue && !isLocked {
                // Don't lock immediately when enabling
            }
        }
    }

    var lockOnBackground: Bool {
        get { settingsService.lockOnBackground }
        set {
            var settings = settingsService
            settings.lockOnBackground = newValue
        }
    }

    // MARK: - Initialization

    init(
        biometricService: BiometricServiceProtocol = BiometricService(),
        settingsService: SettingsServiceProtocol = SettingsService()
    ) {
        self.biometricService = biometricService
        self.settingsService = settingsService

        // Start locked if biometric lock is enabled
        if settingsService.isBiometricLockEnabled {
            isLocked = true
        }
    }

    // MARK: - Actions

    /// Lock the app
    func lock() {
        guard isBiometricLockEnabled else { return }
        isLocked = true
        authenticationError = nil
    }

    /// Attempt to unlock with biometrics
    func unlock() async {
        guard isLocked else { return }

        isAuthenticating = true
        authenticationError = nil

        do {
            let success = try await biometricService.authenticate(
                reason: "Unlock Ash to access your secure conversations"
            )

            if success {
                isLocked = false
            } else {
                authenticationError = "Authentication failed"
            }
        } catch let error as BiometricError {
            authenticationError = error.localizedDescription
        } catch {
            authenticationError = error.localizedDescription
        }

        isAuthenticating = false
    }

    /// Called when app enters background
    func appDidEnterBackground() {
        if isBiometricLockEnabled && lockOnBackground {
            lock()
        }
    }

    /// Called when app becomes active
    func appDidBecomeActive() {
        if isLocked {
            Task {
                await unlock()
            }
        }
    }

    /// Enable biometric lock with initial authentication
    func enableBiometricLock() async -> Bool {
        guard canUseBiometrics else {
            authenticationError = BiometricError.notAvailable.localizedDescription
            return false
        }

        do {
            let success = try await biometricService.authenticate(
                reason: "Authenticate to enable biometric lock"
            )

            if success {
                var settings = settingsService
                settings.isBiometricLockEnabled = true
                return true
            }
        } catch let error as BiometricError {
            authenticationError = error.localizedDescription
        } catch {
            authenticationError = error.localizedDescription
        }

        return false
    }

    /// Disable biometric lock
    func disableBiometricLock() {
        var settings = settingsService
        settings.isBiometricLockEnabled = false
        isLocked = false
    }
}
