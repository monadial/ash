package com.monadial.ash.domain.usecases.conversation

import com.monadial.ash.core.common.AppResult
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.repositories.ConversationRepository
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject

/**
 * Use case for retrieving conversations.
 *
 * Provides a clean interface for ViewModels to access conversation data
 * without directly depending on repository implementation details.
 */
class GetConversationsUseCase @Inject constructor(
    private val conversationRepository: ConversationRepository
) {
    /**
     * Observable list of all conversations.
     */
    val conversations: StateFlow<List<Conversation>>
        get() = conversationRepository.conversations

    /**
     * Load all conversations from storage.
     */
    suspend operator fun invoke(): AppResult<List<Conversation>> {
        return conversationRepository.loadConversations()
    }

    /**
     * Get a specific conversation by ID.
     */
    suspend fun getById(id: String): AppResult<Conversation> {
        return conversationRepository.getConversation(id)
    }

    /**
     * Refresh conversations from storage.
     */
    suspend fun refresh(): AppResult<List<Conversation>> {
        return conversationRepository.loadConversations()
    }
}
