//
//  Dependencies.swift
//  Ash
//
//  Core Layer - Dependency Injection Container
//  Provides all dependencies via SwiftUI Environment
//

import SwiftUI

// MARK: - Dependency Container

/// Central container holding all app dependencies
/// Instantiated once at app launch, injected via Environment
final class Dependencies: ObservableObject, @unchecked Sendable {
    // MARK: - Repositories

    let conversationRepository: ConversationRepository
    let messageRepository: MessageRepository

    // MARK: - Services

    let keychainService: KeychainServiceProtocol
    let cryptoService: CryptoServiceProtocol
    @MainActor let hapticService: HapticServiceProtocol
    let settingsService: SettingsServiceProtocol
    let locationService: LocationServiceProtocol
    let relayService: RelayServiceProtocol?
    let pushNotificationService: PushNotificationService

    /// Pad manager using Rust core for allocation logic (shared with Android)
    let padManager: PadManagerProtocol

    // MARK: - Use Cases

    let sendMessageUseCase: SendMessageUseCaseProtocol
    let receiveMessageUseCase: ReceiveMessageUseCaseProtocol
    let burnConversationUseCase: BurnConversationUseCaseProtocol
    let performCeremonyUseCase: PerformCeremonyUseCaseProtocol

    // MARK: - Fresh Install Detection

    private static let hasLaunchedKey = "com.monadial.ash.hasLaunchedBefore"

    /// Check if this is a fresh install and wipe Keychain if so
    /// UserDefaults is deleted on uninstall, but Keychain persists
    private static func handleFreshInstallIfNeeded(keychain: KeychainServiceProtocol) {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: hasLaunchedKey)

        if !hasLaunchedBefore {
            Log.info(.app, "Fresh install detected - wiping stale Keychain data")

            // Wipe all Keychain data from previous install
            do {
                try keychain.deleteAll()
                Log.info(.app, "Keychain wiped successfully")
            } catch {
                Log.warning(.app, "Failed to wipe Keychain")
            }

            // Mark as launched
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
            UserDefaults.standard.synchronize()
        }
    }

    // MARK: - Initialization

    @MainActor
    init(
        conversationRepository: ConversationRepository? = nil,
        padManager: PadManagerProtocol? = nil,
        messageRepository: MessageRepository? = nil,
        keychainService: KeychainServiceProtocol? = nil,
        cryptoService: CryptoServiceProtocol? = nil,
        hapticService: HapticServiceProtocol? = nil,
        settingsService: SettingsServiceProtocol? = nil,
        locationService: LocationServiceProtocol? = nil,
        relayService: RelayServiceProtocol? = nil,
        pushNotificationService: PushNotificationService? = nil
    ) {
        // Create services
        let keychain = keychainService ?? KeychainService()

        // Handle fresh install - wipe stale Keychain data
        Self.handleFreshInstallIfNeeded(keychain: keychain)

        let crypto = cryptoService ?? CryptoService()
        let haptic = hapticService ?? HapticService()
        let settings = settingsService ?? SettingsService()
        let location = locationService ?? LocationService()
        let push = pushNotificationService ?? PushNotificationService(keychainService: keychain)

        // Create repositories
        // Ephemeral-only: all messages in memory, wiped on app close
        let convRepo = conversationRepository ?? KeychainConversationRepository(keychainService: keychain)
        let padMgr = padManager ?? PadManager(keychainService: keychain)
        let msgRepo = messageRepository ?? InMemoryMessageRepository()

        self.keychainService = keychain
        self.conversationRepository = convRepo
        self.padManager = padMgr
        self.messageRepository = msgRepo

        self.cryptoService = crypto
        self.hapticService = haptic
        self.settingsService = settings
        self.locationService = location
        self.pushNotificationService = push

        // Relay service is created dynamically per conversation
        // This is just a default/fallback for testing
        self.relayService = relayService

        // Create use cases
        self.sendMessageUseCase = SendMessageUseCase(
            padManager: padMgr,
            conversationRepository: convRepo,
            cryptoService: crypto
        )

        self.receiveMessageUseCase = ReceiveMessageUseCase(
            padManager: padMgr,
            conversationRepository: convRepo,
            cryptoService: crypto
        )

        self.burnConversationUseCase = BurnConversationUseCase(
            conversationRepository: convRepo,
            padManager: padMgr,
            messageRepository: msgRepo,
            relayServiceFactory: { url in
                try? RelayService(baseURLString: url)
            }
        )

        self.performCeremonyUseCase = PerformCeremonyUseCase(
            cryptoService: crypto,
            conversationRepository: convRepo,
            padManager: padMgr,
            relayServiceFactory: { url in
                try? RelayService(baseURLString: url)
            }
        )
    }

    /// Create a relay service for a specific URL
    func createRelayService(for url: String) -> RelayServiceProtocol? {
        return try? RelayService(baseURLString: url)
    }

    /// Create a relay service using the default settings
    func createDefaultRelayService() -> RelayServiceProtocol? {
        return try? RelayService(baseURLString: settingsService.relayServerURL)
    }

}

// MARK: - Environment Key

private struct DependenciesKey: EnvironmentKey {
    static var defaultValue: Dependencies {
        // Create on main actor when first accessed
        MainActor.assumeIsolated {
            Dependencies()
        }
    }
}

extension EnvironmentValues {
    var dependencies: Dependencies {
        get { self[DependenciesKey.self] }
        set { self[DependenciesKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Inject dependencies into the view hierarchy
    func withDependencies(_ dependencies: Dependencies) -> some View {
        self.environment(\.dependencies, dependencies)
    }
}
