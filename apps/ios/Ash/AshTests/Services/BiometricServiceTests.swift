//
//  BiometricServiceTests.swift
//  AshTests
//
//  Unit tests for BiometricService and BiometricType
//

import Testing
@testable import Ash

// MARK: - BiometricType Tests

struct BiometricTypeTests {

    @Test func displayName_returnsCorrectNames() {
        #expect(BiometricType.none.displayName == "None")
        #expect(BiometricType.touchID.displayName == "Touch ID")
        #expect(BiometricType.faceID.displayName == "Face ID")
        #expect(BiometricType.opticID.displayName == "Optic ID")
    }

    @Test func iconName_returnsCorrectIcons() {
        #expect(BiometricType.none.iconName == "lock.slash")
        #expect(BiometricType.touchID.iconName == "touchid")
        #expect(BiometricType.faceID.iconName == "faceid")
        #expect(BiometricType.opticID.iconName == "opticid")
    }
}

// MARK: - BiometricError Tests

struct BiometricErrorTests {

    @Test func localizedDescription_notAvailable() {
        let error = BiometricError.notAvailable
        #expect(error.localizedDescription.contains("not available"))
    }

    @Test func localizedDescription_notEnrolled() {
        let error = BiometricError.notEnrolled
        #expect(error.localizedDescription.contains("enrolled"))
    }

    @Test func localizedDescription_authenticationFailed() {
        let error = BiometricError.authenticationFailed
        #expect(error.localizedDescription.contains("failed"))
    }

    @Test func localizedDescription_userCancelled() {
        let error = BiometricError.userCancelled
        #expect(error.localizedDescription.contains("cancelled"))
    }

    @Test func localizedDescription_systemCancelled() {
        let error = BiometricError.systemCancelled
        #expect(error.localizedDescription.contains("cancelled"))
    }

    @Test func localizedDescription_passcodeNotSet() {
        let error = BiometricError.passcodeNotSet
        #expect(error.localizedDescription.contains("passcode"))
    }

    @Test func localizedDescription_biometryLockout() {
        let error = BiometricError.biometryLockout
        #expect(error.localizedDescription.contains("locked"))
    }

    @Test func localizedDescription_unknown() {
        let error = BiometricError.unknown("Custom error message")
        #expect(error.localizedDescription == "Custom error message")
    }
}

// MARK: - MockBiometricService Tests

struct MockBiometricServiceTests {

    @Test func authenticate_success() async throws {
        let service = MockBiometricService()
        service.shouldSucceed = true

        let result = try await service.authenticate(reason: "Test reason")

        #expect(result == true)
        #expect(service.authenticateCalled == true)
        #expect(service.authenticateReason == "Test reason")
        #expect(service.authenticateCallCount == 1)
    }

    @Test func authenticate_failure() async throws {
        let service = MockBiometricService()
        service.shouldSucceed = false

        let result = try await service.authenticate(reason: "Test")

        #expect(result == false)
    }

    @Test func authenticate_throwsError() async {
        let service = MockBiometricService()
        service.errorToThrow = .userCancelled

        do {
            _ = try await service.authenticate(reason: "Test")
            Issue.record("Expected error to be thrown")
        } catch let error as BiometricError {
            #expect(error == .userCancelled)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func canUseBiometrics_returnsConfiguredValue() {
        let service = MockBiometricService()

        service.mockCanUseBiometrics = true
        #expect(service.canUseBiometrics == true)

        service.mockCanUseBiometrics = false
        #expect(service.canUseBiometrics == false)
    }

    @Test func availableBiometricType_returnsConfiguredType() {
        let service = MockBiometricService()

        service.mockBiometricType = .faceID
        #expect(service.availableBiometricType == .faceID)

        service.mockBiometricType = .touchID
        #expect(service.availableBiometricType == .touchID)
    }

    @Test func reset_clearsState() async throws {
        let service = MockBiometricService()
        _ = try await service.authenticate(reason: "Test")

        service.reset()

        #expect(service.authenticateCalled == false)
        #expect(service.authenticateCallCount == 0)
        #expect(service.shouldSucceed == true)
    }
}
