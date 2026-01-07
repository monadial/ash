//
//  ConversationRepository.swift
//  Ash
//

import Foundation

protocol ConversationRepository: Sendable {
    func getAll() async throws -> [Conversation]
    func get(id: String) async throws -> Conversation?
    func save(_ conversation: Conversation) async throws
    func burn(_ conversation: Conversation) async throws
    func burnAll() async throws
}

// PadRepository is replaced by PadManagerProtocol in Core/Services/PadManager.swift
// The old PadRepository used single-direction consumption; PadManager uses bidirectional
// consumption via Rust Pad (shared with Android)

protocol MessageRepository: Sendable {
    func getMessages(for conversationId: String) async -> [Message]
    func addMessage(_ message: Message, to conversationId: String) async
    func replaceMessage(_ message: Message, in conversationId: String) async
    func pruneExpired() async
    func clear(for conversationId: String) async
    func clearAll() async
    /// Check if a message with the given sequence already exists (for deduplication)
    func hasMessage(withSequence sequence: UInt64, in conversationId: String) async -> Bool
    /// Securely wipe all messages by overwriting with zeros before deallocation
    /// Call this when the app is going to background or terminating
    func secureWipeAll() async
}

// Default implementation for repositories that don't need secure wipe (e.g., persistent storage)
extension MessageRepository {
    func secureWipeAll() async {
        // Default: just clear all (persistent storage doesn't need memory zeroing)
        await clearAll()
    }
}
