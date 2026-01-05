//
//  InMemoryMessageRepository.swift
//  Ash
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

    func hasMessage(withSequence sequence: UInt64, in conversationId: String) async -> Bool {
        guard let msgs = messages[conversationId] else { return false }
        return msgs.contains { $0.sequence == sequence }
    }
}
