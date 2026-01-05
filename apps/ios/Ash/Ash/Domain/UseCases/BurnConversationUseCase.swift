//
//  BurnConversationUseCase.swift
//  Ash
//
//  Domain Layer - Use Case for securely destroying conversations
//  Simplified ephemeral design - immediate burn only
//

import Foundation

/// Use case for burning (securely destroying) a conversation
/// Simplified: always immediate burn, no modes to choose from
protocol BurnConversationUseCaseProtocol: Sendable {
    /// Burn a single conversation (always immediate)
    func execute(conversation: Conversation) async throws

    /// Burn all conversations immediately (panic wipe)
    func executeAll() async throws

    /// Mark a conversation as burned by peer (called when relay reports burn)
    func markPeerBurned(conversation: Conversation) async throws -> Conversation
}

/// Factory for creating relay services
typealias RelayServiceFactory = @Sendable (String) -> RelayServiceProtocol?

/// Factory for getting conversation-specific message repository
typealias MessageRepositoryFactory = @Sendable (Conversation) -> MessageRepository

/// Implementation of burn conversation use case
final class BurnConversationUseCase: BurnConversationUseCaseProtocol, Sendable {
    private let conversationRepository: ConversationRepository
    private let padManager: PadManagerProtocol
    private let messageRepository: MessageRepository
    private let relayServiceFactory: RelayServiceFactory

    init(
        conversationRepository: ConversationRepository,
        padManager: PadManagerProtocol,
        messageRepository: MessageRepository,
        relayServiceFactory: @escaping RelayServiceFactory
    ) {
        self.conversationRepository = conversationRepository
        self.padManager = padManager
        self.messageRepository = messageRepository
        self.relayServiceFactory = relayServiceFactory
    }

    func execute(conversation: Conversation) async throws {
        Log.warning(.storage, "Executing burn for \(conversation.id.prefix(8))")

        let burnToken = conversation.burnToken

        // Order matters for security:
        // 1. Wipe the pad first (most sensitive)
        try await padManager.wipePad(for: conversation.id)

        // 2. Clear messages
        await messageRepository.clear(for: conversation.id)

        // 3. Remove conversation record
        try await conversationRepository.burn(conversation)

        // 4. Notify relay server to burn (fire-and-forget)
        notifyRelayBurn(conversation: conversation, burnToken: burnToken)
    }

    /// Mark conversation as burned by peer (called when relay reports burn)
    func markPeerBurned(conversation: Conversation) async throws -> Conversation {
        Log.warning(.storage, "Peer burned conversation \(conversation.id.prefix(8))")

        // Immediate burn - wipe our data when peer burns
        try await padManager.wipePad(for: conversation.id)
        await messageRepository.clear(for: conversation.id)
        try await conversationRepository.burn(conversation)

        var updated = conversation
        updated.peerBurnedAt = Date()
        return updated
    }

    /// Fire-and-forget relay notification
    private func notifyRelayBurn(conversation: Conversation, burnToken: String) {
        guard !burnToken.isEmpty else {
            Log.warning(.relay, "No burn token available, skipping relay notification")
            return
        }
        if let relay = relayServiceFactory(conversation.relayURL) {
            Task {
                do {
                    try await relay.burnConversation(conversationId: conversation.id, burnToken: burnToken)
                    Log.info(.relay, "Burn notification sent")
                } catch {
                    Log.warning(.relay, "Burn notification failed (non-critical)")
                }
            }
        }
    }

    func executeAll() async throws {
        let conversations = try await conversationRepository.getAll()

        // Wipe all pads
        try await padManager.wipeAllPads()

        // Clear all messages
        await messageRepository.clearAll()

        // Remove all conversation records
        try await conversationRepository.burnAll()

        // Notify relay server for each conversation (fire-and-forget)
        for conversation in conversations {
            if let relay = relayServiceFactory(conversation.relayURL), !conversation.burnToken.isEmpty {
                Task {
                    do {
                        try await relay.burnConversation(conversationId: conversation.id, burnToken: conversation.burnToken)
                        Log.info(.relay, "Burn notification sent")
                    } catch {
                        Log.warning(.relay, "Burn notification failed (non-critical)")
                    }
                }
            }
        }
    }
}
