//
//  MockConversationRepository.swift
//  AshTests
//
//  Mock implementation of ConversationRepository for testing
//

import Foundation
@testable import Ash

/// Mock conversation repository for testing
actor MockConversationRepository: ConversationRepository {
    // MARK: - Storage

    private var conversations: [String: Conversation] = [:]

    // MARK: - Call Tracking

    private(set) var getAllCalled = false
    private(set) var getCalled = false
    private(set) var saveCalled = false
    private(set) var burnCalled = false
    private(set) var lastSavedConversation: Conversation?

    // MARK: - Protocol Implementation

    func getAll() async throws -> [Conversation] {
        getAllCalled = true
        return Array(conversations.values)
    }

    func get(id: String) async throws -> Conversation? {
        getCalled = true
        return conversations[id]
    }

    func save(_ conversation: Conversation) async throws {
        saveCalled = true
        lastSavedConversation = conversation
        conversations[conversation.id] = conversation
    }

    func burn(_ conversation: Conversation) async throws {
        burnCalled = true
        conversations.removeValue(forKey: conversation.id)
    }

    func burnAll() async throws {
        conversations.removeAll()
    }

    // MARK: - Test Helpers

    func reset() {
        conversations.removeAll()
        getAllCalled = false
        getCalled = false
        saveCalled = false
        burnCalled = false
        lastSavedConversation = nil
    }

    /// Add a conversation for testing
    func addConversation(_ conversation: Conversation) {
        conversations[conversation.id] = conversation
    }
}
