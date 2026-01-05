//
//  KeychainConversationRepository.swift
//  Ash
//

import Foundation

actor KeychainConversationRepository: ConversationRepository {
    private let keychainService: KeychainServiceProtocol
    private var cache: [String: Conversation] = [:]
    private var hasLoaded = false
    private let keyPrefix = "conversation."

    init(keychainService: KeychainServiceProtocol = KeychainService()) {
        self.keychainService = keychainService
    }

    func getAll() async throws -> [Conversation] {
        try await loadIfNeeded()
        return cache.values.sorted {
            if $0.lastActivity == $1.lastActivity {
                return $0.activitySequence > $1.activitySequence
            }
            return $0.lastActivity > $1.lastActivity
        }
    }

    func get(id: String) async throws -> Conversation? {
        try await loadIfNeeded()
        return cache[id]
    }

    func save(_ conversation: Conversation) async throws {
        let data = try JSONEncoder().encode(conversation)
        try keychainService.store(data: data, for: keychainKey(for: conversation.id))
        cache[conversation.id] = conversation
    }

    func burn(_ conversation: Conversation) async throws {
        try keychainService.delete(for: keychainKey(for: conversation.id))
        cache.removeValue(forKey: conversation.id)
    }

    func burnAll() async throws {
        let keys = try keychainService.allKeys(withPrefix: keyPrefix)
        for key in keys {
            try keychainService.delete(for: key)
        }
        cache.removeAll()
    }

    private func keychainKey(for id: String) -> String {
        "\(keyPrefix)\(id)"
    }

    private func loadIfNeeded() async throws {
        guard !hasLoaded else { return }

        let keys = try keychainService.allKeys(withPrefix: keyPrefix)

        for key in keys {
            guard let data = try keychainService.retrieve(for: key) else { continue }

            do {
                let conversation = try JSONDecoder().decode(Conversation.self, from: data)
                cache[conversation.id] = conversation
            } catch {
                Log.warning(.storage, "Removing invalid conversation entry")
                try? keychainService.delete(for: key)
            }
        }

        hasLoaded = true
        Log.debug(.storage, "Loaded \(cache.count) conversations from Keychain")
    }
}
