//
//  MockBiometricService.swift
//  AshTests
//
//  Mock implementation of BiometricServiceProtocol for testing
//

import Foundation
@testable import Ash

/// Mock biometric service for testing
final class MockBiometricService: BiometricServiceProtocol, @unchecked Sendable {
    // MARK: - Configuration

    var mockBiometricType: BiometricType = .faceID
    var mockCanUseBiometrics: Bool = true
    var shouldSucceed: Bool = true
    var errorToThrow: BiometricError?

    // MARK: - Call Tracking

    private(set) var authenticateCalled = false
    private(set) var authenticateReason: String?
    private(set) var authenticateCallCount = 0

    // MARK: - Protocol Implementation

    var availableBiometricType: BiometricType {
        mockBiometricType
    }

    var canUseBiometrics: Bool {
        mockCanUseBiometrics
    }

    func authenticate(reason: String) async throws -> Bool {
        authenticateCalled = true
        authenticateReason = reason
        authenticateCallCount += 1

        if let error = errorToThrow {
            throw error
        }

        return shouldSucceed
    }

    // MARK: - Reset

    func reset() {
        authenticateCalled = false
        authenticateReason = nil
        authenticateCallCount = 0
        shouldSucceed = true
        errorToThrow = nil
    }
}
