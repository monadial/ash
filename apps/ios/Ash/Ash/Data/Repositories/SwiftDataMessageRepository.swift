//
//  SwiftDataMessageRepository.swift
//  Ash
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataMessageRepository: MessageRepository {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelContext = modelContainer.mainContext
    }

    func getMessages(for conversationId: String) async -> [Message] {
        let predicate = #Predicate<PersistedMessage> { $0.conversationId == conversationId }
        let descriptor = FetchDescriptor<PersistedMessage>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        do {
            let persisted = try modelContext.fetch(descriptor)
            return persisted.compactMap { try? $0.toMessage() }
        } catch {
            Log.error(.storage, "Failed to fetch messages: \(error)")
            return []
        }
    }

    func addMessage(_ message: Message, to conversationId: String) async {
        // Check for duplicate
        let messageId = message.id
        let predicate = #Predicate<PersistedMessage> { $0.id == messageId }
        let descriptor = FetchDescriptor<PersistedMessage>(predicate: predicate)

        do {
            let existing = try modelContext.fetch(descriptor)
            if !existing.isEmpty {
                return // Skip duplicate
            }

            let persisted = try PersistedMessage(from: message, conversationId: conversationId)
            modelContext.insert(persisted)
            try modelContext.save()
        } catch {
            Log.error(.storage, "Failed to add message: \(error)")
        }
    }

    func replaceMessage(_ message: Message, in conversationId: String) async {
        let messageId = message.id
        let predicate = #Predicate<PersistedMessage> { $0.id == messageId }
        let descriptor = FetchDescriptor<PersistedMessage>(predicate: predicate)

        do {
            let existing = try modelContext.fetch(descriptor)
            if let persisted = existing.first {
                // Update existing record
                let contentData = try JSONEncoder().encode(message.content)
                persisted.contentData = contentData
                persisted.expiresAt = message.expiresAt
                let (statusRaw, reason) = message.deliveryStatus.encoded
                persisted.deliveryStatusRaw = statusRaw
                persisted.failureReason = reason
                try modelContext.save()
            }
        } catch {
            Log.error(.storage, "Failed to replace message: \(error)")
        }
    }

    func pruneExpired() async {
        let now = Date()
        // Fetch all and filter in memory - Predicate doesn't support optional comparison well
        let descriptor = FetchDescriptor<PersistedMessage>()

        do {
            let all = try modelContext.fetch(descriptor)
            let expired = all.filter { message in
                guard let expiresAt = message.expiresAt else { return false }
                return expiresAt <= now
            }
            for message in expired {
                modelContext.delete(message)
            }
            if !expired.isEmpty {
                try modelContext.save()
                Log.debug(.storage, "Pruned \(expired.count) expired messages")
            }
        } catch {
            Log.error(.storage, "Failed to prune expired messages: \(error)")
        }
    }

    func clear(for conversationId: String) async {
        let predicate = #Predicate<PersistedMessage> { $0.conversationId == conversationId }
        let descriptor = FetchDescriptor<PersistedMessage>(predicate: predicate)

        do {
            let messages = try modelContext.fetch(descriptor)
            for message in messages {
                modelContext.delete(message)
            }
            try modelContext.save()
            Log.debug(.storage, "Cleared messages for conversation")
        } catch {
            Log.error(.storage, "Failed to clear messages: \(error)")
        }
    }

    func clearAll() async {
        do {
            try modelContext.delete(model: PersistedMessage.self)
            try modelContext.save()
            Log.debug(.storage, "Cleared all persisted messages")
        } catch {
            Log.error(.storage, "Failed to clear all messages: \(error)")
        }
    }

    func hasMessage(withSequence sequence: UInt64, in conversationId: String) async -> Bool {
        let descriptor = FetchDescriptor<PersistedMessage>(
            predicate: #Predicate<PersistedMessage> { msg in
                msg.conversationId == conversationId && msg.sequence == sequence
            }
        )

        do {
            let count = try modelContext.fetchCount(descriptor)
            return count > 0
        } catch {
            Log.error(.storage, "Failed to check for message sequence: \(error)")
            return false
        }
    }
}
