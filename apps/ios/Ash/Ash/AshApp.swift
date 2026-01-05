//
//  AshApp.swift
//  Ash
//
//  Created by Tomas Mihalicka on 29/12/2025.
//

import SwiftUI

@main
struct AshApp: App {
    /// App delegate for system callbacks (push notifications, etc.)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Dependency container - single source of truth for all dependencies
    @StateObject private var dependencies = Dependencies()

    /// Root view model
    @State private var appViewModel: AppViewModel?

    /// App lock view model for biometric authentication
    @State private var lockViewModel = AppLockViewModel()

    /// Track scene phase for background/foreground detection
    @Environment(\.scenePhase) private var scenePhase

    /// Track if push notifications have been set up
    @State private var pushNotificationsSetUp = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if let viewModel = appViewModel {
                        RootView(viewModel: viewModel, lockViewModel: lockViewModel)
                            .withDependencies(dependencies)
                    } else {
                        LoadingScreen()
                            .task {
                                appViewModel = AppViewModel(dependencies: dependencies)
                            }
                    }
                }
                .tint(Color.ashSecure)
                .preferredColorScheme(nil) // Support both light and dark

                // Lock screen overlay
                if lockViewModel.isLocked {
                    LockScreen(viewModel: lockViewModel)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: lockViewModel.isLocked)
            .onChange(of: scenePhase) { oldPhase, newPhase in
                switch newPhase {
                case .background:
                    lockViewModel.appDidEnterBackground()
                case .active:
                    lockViewModel.appDidBecomeActive()
                    // Re-register for push when app becomes active
                    if pushNotificationsSetUp {
                        dependencies.pushNotificationService.registerForRemoteNotifications()
                    }
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            .task {
                await setupPushNotifications()
            }
        }
    }

    // MARK: - Push Notification Setup

    @MainActor
    private func setupPushNotifications() async {
        // Connect AppDelegate to push service
        appDelegate.pushNotificationService = dependencies.pushNotificationService

        // Check current authorization status
        let status = await dependencies.pushNotificationService.getAuthorizationStatus()

        switch status {
        case .notDetermined:
            // Request authorization on first launch
            do {
                let granted = try await dependencies.pushNotificationService.requestAuthorization()
                if granted {
                    dependencies.pushNotificationService.registerForRemoteNotifications()
                }
            } catch {
                Log.error(.push, "Failed to request push notification authorization: \(error)")
            }

        case .authorized, .provisional, .ephemeral:
            // Already authorized - register for remote notifications
            dependencies.pushNotificationService.registerForRemoteNotifications()

        case .denied:
            Log.info(.push, "Push notifications denied by user")

        @unknown default:
            break
        }

        pushNotificationsSetUp = true
    }
}

// MARK: - Root View

/// Root navigation container
struct RootView: View {
    @Bindable var viewModel: AppViewModel
    @Bindable var lockViewModel: AppLockViewModel

    var body: some View {
        NavigationStack {
            ConversationsScreen(viewModel: viewModel)
                .navigationDestination(item: $viewModel.selectedConversation) { conversation in
                    MessagingScreen(
                        conversation: conversation,
                        onBurn: {
                            Task { await viewModel.burnConversation(conversation) }
                        },
                        onRename: { newName in
                            Task { await viewModel.renameConversation(conversation, to: newName) }
                        },
                        onUpdateRelayURL: { url in
                            Task { await viewModel.updateConversationRelayURL(conversation, url: url) }
                        },
                        onUpdateColor: { color in
                            Task { await viewModel.updateConversationColor(conversation, color: color) }
                        },
                        onDismiss: {
                            // Reload conversations to get updated state (pad consumption, cursor, etc.)
                            await viewModel.loadConversations()
                        }
                    )
                }
        }
        .sheet(isPresented: $viewModel.isShowingCeremony) {
            CeremonyScreen(
                viewModel: viewModel.ceremonyViewModel,
                onComplete: { conversation in
                    Task { await viewModel.handleCeremonyCompleted(conversation) }
                },
                onCancel: {
                    viewModel.isShowingCeremony = false
                }
            )
        }
        .sheet(isPresented: $viewModel.isShowingSettings) {
            SettingsScreen(
                lockViewModel: lockViewModel,
                onBurnAll: {
                    Task { await viewModel.burnAllConversations() }
                },
                onRelaySettingsChanged: {
                    // Settings changed - app needs restart for full effect
                    // Future: implement dynamic relay service refresh
                }
            )
        }
        .task {
            await viewModel.loadConversations()
        }
    }
}
