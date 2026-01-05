//
//  BiometricService.swift
//  Ash
//

import Foundation
import LocalAuthentication

enum BiometricType: Sendable {
    case none
    case touchID
    case faceID
    case opticID

    var displayName: String {
        switch self {
        case .none: return "None"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        }
    }

    var iconName: String {
        switch self {
        case .none: return "lock.slash"
        case .touchID: return "touchid"
        case .faceID: return "faceid"
        case .opticID: return "opticid"
        }
    }
}

enum BiometricError: Error, Sendable, Equatable {
    case notAvailable
    case notEnrolled
    case authenticationFailed
    case userCancelled
    case systemCancelled
    case passcodeNotSet
    case biometryLockout
    case unknown(String)

    var localizedDescription: String {
        switch self {
        case .notAvailable: return "Biometric authentication is not available on this device."
        case .notEnrolled: return "No biometric data is enrolled. Please set up Face ID or Touch ID in Settings."
        case .authenticationFailed: return "Authentication failed. Please try again."
        case .userCancelled: return "Authentication was cancelled."
        case .systemCancelled: return "Authentication was cancelled by the system."
        case .passcodeNotSet: return "Please set a device passcode to use biometric authentication."
        case .biometryLockout: return "Biometric authentication is locked. Please use your device passcode."
        case .unknown(let message): return message
        }
    }
}

protocol BiometricServiceProtocol: Sendable {
    var availableBiometricType: BiometricType { get }
    var canUseBiometrics: Bool { get }
    func authenticate(reason: String) async throws -> Bool
}

final class BiometricService: BiometricServiceProtocol, @unchecked Sendable {
    private let context = LAContext()

    var availableBiometricType: BiometricType {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .touchID:
            return .touchID
        case .faceID:
            return .faceID
        case .opticID:
            return .opticID
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }

    var canUseBiometrics: Bool {
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw mapError(error)
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch let authError as NSError {
            throw mapError(authError)
        }
    }

    private func mapError(_ error: NSError?) -> BiometricError {
        guard let error = error else {
            return .unknown("Unknown error")
        }

        switch error.code {
        case LAError.biometryNotAvailable.rawValue:
            return .notAvailable
        case LAError.biometryNotEnrolled.rawValue:
            return .notEnrolled
        case LAError.authenticationFailed.rawValue:
            return .authenticationFailed
        case LAError.userCancel.rawValue:
            return .userCancelled
        case LAError.systemCancel.rawValue:
            return .systemCancelled
        case LAError.passcodeNotSet.rawValue:
            return .passcodeNotSet
        case LAError.biometryLockout.rawValue:
            return .biometryLockout
        default:
            return .unknown(error.localizedDescription)
        }
    }
}
