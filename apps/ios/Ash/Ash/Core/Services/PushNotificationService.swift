//
//  PushNotificationService.swift
//  Ash
//
//  Core Layer - Push notification management
//  Handles APNS registration, permissions, and device token lifecycle
//

import Foundation
import UserNotifications
import UIKit

// MARK: - Protocol

protocol PushNotificationServiceProtocol: Sendable {
    /// Request push notification authorization from the user
    func requestAuthorization() async throws -> Bool

    /// Register for remote notifications with APNS
    @MainActor func registerForRemoteNotifications()

    /// Handle device token received from APNS
    func handleDeviceToken(_ token: Data)

    /// Handle failed registration
    func handleRegistrationError(_ error: Error)

    /// Register device with relay for a specific conversation
    func registerWithRelay(
        conversationId: String,
        authToken: String,
        relayService: RelayServiceProtocol
    ) async throws

    /// Get current authorization status
    func getAuthorizationStatus() async -> UNAuthorizationStatus

    /// Get the current device token (hex string)
    var currentDeviceToken: String? { get }

    /// Check if push notifications are enabled
    var isEnabled: Bool { get }
}

// MARK: - Errors

enum PushNotificationError: Error, Sendable {
    case authorizationDenied
    case noDeviceToken
    case registrationFailed(Error)
    case relayRegistrationFailed(Error)
}

extension PushNotificationError: CustomStringConvertible {
    var description: String {
        switch self {
        case .authorizationDenied:
            return "Push notification authorization denied"
        case .noDeviceToken:
            return "No device token available"
        case .registrationFailed(let error):
            return "Registration failed: \(error.localizedDescription)"
        case .relayRegistrationFailed(let error):
            return "Relay registration failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Implementation

final class PushNotificationService: PushNotificationServiceProtocol, @unchecked Sendable {
    private let keychainService: KeychainServiceProtocol
    private let notificationCenter: UNUserNotificationCenter

    /// Keychain key for storing device token
    private static let deviceTokenKey = "com.monadial.ash.push.deviceToken"

    /// Thread-safe storage for current device token
    private let tokenLock = NSLock()
    private var _deviceToken: String?

    var currentDeviceToken: String? {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        return _deviceToken
    }

    var isEnabled: Bool {
        currentDeviceToken != nil
    }

    init(
        keychainService: KeychainServiceProtocol,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.keychainService = keychainService
        self.notificationCenter = notificationCenter

        // Load cached device token from keychain
        loadCachedToken()
    }

    // MARK: - Authorization

    func requestAuthorization() async throws -> Bool {
        Log.info(.push, "Requesting push notification authorization")

        do {
            // Request authorization for silent notifications (no alerts needed for ASH)
            // We use silent pushes to wake the app for background message fetching
            let granted = try await notificationCenter.requestAuthorization(
                options: [.badge]  // Minimal permissions - just badge for silent push
            )

            if granted {
                Log.info(.push, "Push notification authorization granted")
            } else {
                Log.warning(.push, "Push notification authorization denied by user")
            }

            return granted
        } catch {
            Log.error(.push, "Failed to request authorization: \(error.localizedDescription)")
            throw PushNotificationError.registrationFailed(error)
        }
    }

    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Registration

    @MainActor
    func registerForRemoteNotifications() {
        Log.info(.push, "Registering for remote notifications with APNS")
        UIApplication.shared.registerForRemoteNotifications()
    }

    func handleDeviceToken(_ token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()

        tokenLock.lock()
        let previousToken = _deviceToken
        _deviceToken = tokenString
        tokenLock.unlock()

        // Check if token changed
        if previousToken != tokenString {
            Log.info(.push, "Device token updated (length: \(tokenString.count) chars)")

            // Persist to keychain
            do {
                try keychainService.store(
                    data: tokenString.data(using: .utf8) ?? Data(),
                    for: Self.deviceTokenKey
                )
                Log.debug(.push, "Device token persisted to keychain")
            } catch {
                Log.error(.push, "Failed to persist device token: \(error)")
            }
        } else {
            Log.debug(.push, "Device token unchanged")
        }
    }

    func handleRegistrationError(_ error: Error) {
        Log.error(.push, "Remote notification registration failed: \(error.localizedDescription)")

        // Clear cached token on error
        tokenLock.lock()
        _deviceToken = nil
        tokenLock.unlock()
    }

    // MARK: - Relay Registration

    func registerWithRelay(
        conversationId: String,
        authToken: String,
        relayService: RelayServiceProtocol
    ) async throws {
        guard let token = currentDeviceToken else {
            Log.warning(.push, "Cannot register with relay - no device token")
            throw PushNotificationError.noDeviceToken
        }

        let shortId = String(conversationId.prefix(8))
        Log.info(.push, "[\(shortId)] Registering device with relay")

        do {
            try await relayService.registerDevice(
                conversationId: conversationId,
                authToken: authToken,
                deviceToken: token
            )
            Log.info(.push, "[\(shortId)] Device registered with relay successfully")
        } catch {
            Log.error(.push, "[\(shortId)] Failed to register with relay: \(error)")
            throw PushNotificationError.relayRegistrationFailed(error)
        }
    }

    // MARK: - Private

    private func loadCachedToken() {
        do {
            if let data = try keychainService.retrieve(for: Self.deviceTokenKey),
               let token = String(data: data, encoding: .utf8) {
                tokenLock.lock()
                _deviceToken = token
                tokenLock.unlock()
                Log.debug(.push, "Loaded cached device token from keychain")
            }
        } catch {
            Log.warning(.push, "Failed to load cached device token: \(error)")
        }
    }
}

// MARK: - Notification Handler

/// Handles incoming push notifications
final class PushNotificationHandler: Sendable {
    /// Called when a silent push notification is received
    /// Returns true if the notification was handled
    static func handleSilentPush(
        userInfo: [AnyHashable: Any],
        completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Log.debug(.push, "Received silent push notification")

        // Check for content-available flag (required for silent push)
        guard let aps = userInfo["aps"] as? [String: Any],
              aps["content-available"] as? Int == 1 else {
            Log.warning(.push, "Push notification missing content-available flag")
            completionHandler(.noData)
            return
        }

        // Extract conversation ID if present (for targeted refresh)
        if let conversationId = userInfo["conversation_id"] as? String {
            let shortId = String(conversationId.prefix(8))
            Log.info(.push, "[\(shortId)] Silent push for conversation")

            // Post notification for the app to handle
            NotificationCenter.default.post(
                name: .pushNotificationReceived,
                object: nil,
                userInfo: ["conversation_id": conversationId]
            )
        } else {
            Log.info(.push, "Silent push - triggering general refresh")

            // Post general refresh notification
            NotificationCenter.default.post(
                name: .pushNotificationReceived,
                object: nil,
                userInfo: nil
            )
        }

        completionHandler(.newData)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a push notification is received (carries conversation_id in userInfo if available)
    static let pushNotificationReceived = Notification.Name("com.monadial.ash.pushNotificationReceived")

    /// Posted when device token is updated
    static let deviceTokenUpdated = Notification.Name("com.monadial.ash.deviceTokenUpdated")
}
