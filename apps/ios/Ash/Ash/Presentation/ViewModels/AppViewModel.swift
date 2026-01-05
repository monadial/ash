//
//  AppViewModel.swift
//  Ash
//
//  Presentation Layer - Root application view model
//

import SwiftUI

/// Root view model managing app-wide state
@MainActor
@Observable
final class AppViewModel {
    // MARK: - Dependencies

    private let dependencies: Dependencies

    // MARK: - State

    private(set) var conversations: [Conversation] = []
    var selectedConversation: Conversation?
    var isShowingCeremony = false
    var isShowingSettings = false

    // Child view models
    private(set) var ceremonyViewModel: CeremonyViewModel

    // MARK: - Initialization

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        self.ceremonyViewModel = CeremonyViewModel(dependencies: dependencies)
    }

    // MARK: - Actions

    func loadConversations() async {
        do {
            conversations = try await dependencies.conversationRepository.getAll()
        } catch {
            // Handle error - in production, show error state
            conversations = []
        }
    }

    func selectConversation(_ conversation: Conversation) {
        dependencies.hapticService.selection()
        selectedConversation = conversation
    }

    func startNewConversation() {
        dependencies.hapticService.medium()
        ceremonyViewModel.reset()
        isShowingCeremony = true
    }

    func showSettings() {
        isShowingSettings = true
    }

    func burnConversation(_ conversation: Conversation) async {
        dependencies.hapticService.heavy()

        do {
            try await dependencies.burnConversationUseCase.execute(conversation: conversation)

            // Update UI with animation to prevent List inconsistency crashes
            withAnimation {
                conversations.removeAll { $0.id == conversation.id }
            }

            // Conversation was burned - deselect if currently selected
            if selectedConversation?.id == conversation.id {
                selectedConversation = nil
            }
        } catch {
            // Handle error
        }
    }

    func renameConversation(_ conversation: Conversation, to newName: String) async {
        dependencies.hapticService.selection()

        do {
            let renamed = conversation.renamed(to: newName.isEmpty ? nil : newName)
            try await dependencies.conversationRepository.save(renamed)
            await loadConversations()

            // Update selected conversation if it was renamed
            if selectedConversation?.id == conversation.id {
                selectedConversation = renamed
            }
        } catch {
            // Handle error
        }
    }

    func updateConversationRelayURL(_ conversation: Conversation, url: String) async {
        dependencies.hapticService.selection()

        do {
            let updated = conversation.withRelayURL(url)
            try await dependencies.conversationRepository.save(updated)
            await loadConversations()

            // Update selected conversation if it was modified
            if selectedConversation?.id == conversation.id {
                selectedConversation = updated
            }
        } catch {
            // Handle error
        }
    }

    func burnAllConversations() async {
        dependencies.hapticService.heavy()

        do {
            try await dependencies.burnConversationUseCase.executeAll()
            conversations = []
            selectedConversation = nil
        } catch {
            // Handle error
        }
    }

    // MARK: - Ceremony Completion

    func handleCeremonyCompleted(_ conversation: Conversation) async {
        isShowingCeremony = false

        // Add the new conversation with animation to prevent List inconsistency crashes
        withAnimation {
            // Only add if not already present (safety check)
            if !conversations.contains(where: { $0.id == conversation.id }) {
                conversations.insert(conversation, at: 0)
            }
        }

        selectedConversation = conversation
    }
}
