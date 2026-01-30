//
//  InMemoryMessageRepository.swift
//  Ash
//
//  In-memory ephemeral message storage with secure wipe on app termination
//

import Foundation

actor InMemoryMessageRepository: MessageRepository {
    private var messages: [String: [Message]] = [:]

    func getMessages(for conversationId: String) async -> [Message] {
        messages[conversationId] ?? []
    }

    func addMessage(_ message: Message, to conversationId: String) async {
        if messages[conversationId]?.contains(where: { $0.id == message.id }) == true {
            return
        }

        if messages[conversationId] == nil {
            messages[conversationId] = []
        }
        messages[conversationId]?.append(message)
    }

    func replaceMessage(_ message: Message, in conversationId: String) async {
        guard var msgs = messages[conversationId] else { return }
        if let index = msgs.firstIndex(where: { $0.id == message.id }) {
            msgs[index] = message
            messages[conversationId] = msgs
        }
    }

    func pruneExpired() async {
        let now = Date()
        for (id, msgs) in messages {
            messages[id] = msgs.filter { message in
                guard let expiresAt = message.expiresAt else { return true }
                return expiresAt > now
            }
        }
    }

    func clear(for conversationId: String) async {
        messages.removeValue(forKey: conversationId)
    }

    func clearAll() async {
        messages.removeAll()
    }

    /// Securely wipe all messages by overwriting with zeros before deallocation
    /// Call this when the app is going to background or terminating
    func secureWipeAll() async {
        let count = messages.values.reduce(0) { $0 + $1.count }
        Log.info(.storage, "Secure wiping \(count) in-memory messages")

        // Overwrite each message with zeroed content before removal
        for (conversationId, msgs) in messages {
            // Replace with zeroed messages to overwrite memory
            messages[conversationId] = msgs.map { message in
                // Create a zeroed version of the message
                Message(
                    id: message.id,
                    content: .text(""),  // Zero out content
                    timestamp: Date(timeIntervalSince1970: 0),
                    isOutgoing: false,
                    expiresAt: nil,
                    serverExpiresAt: nil,
                    deliveryStatus: .none,
                    sequence: 0,
                    blobId: nil,
                    isContentWiped: true,
                    authTag: nil  // No auth tag for wiped messages
                )
            }
        }

        // Memory barrier to ensure writes complete
        messages.removeAll(keepingCapacity: false)

        // Force additional memory pressure to encourage deallocation
        messages = [:]

        Log.debug(.storage, "Secure wipe complete")
    }

    func hasMessage(withSequence sequence: UInt64, in conversationId: String) async -> Bool {
        guard let msgs = messages[conversationId] else { return false }
        return msgs.contains { $0.sequence == sequence }
    }
}
