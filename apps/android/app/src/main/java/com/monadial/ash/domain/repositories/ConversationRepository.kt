package com.monadial.ash.domain.repositories

import com.monadial.ash.core.common.AppResult
import com.monadial.ash.domain.entities.Conversation
import kotlinx.coroutines.flow.StateFlow

/**
 * Repository interface for conversation data operations.
 * Abstracts the data source (encrypted SharedPreferences) from the domain layer.
 */
interface ConversationRepository {

    /**
     * Observable list of all conversations, sorted by last activity.
     */
    val conversations: StateFlow<List<Conversation>>

    /**
     * Load all conversations from storage.
     */
    suspend fun loadConversations(): AppResult<List<Conversation>>

    /**
     * Get a specific conversation by ID.
     */
    suspend fun getConversation(id: String): AppResult<Conversation>

    /**
     * Save a new or updated conversation.
     */
    suspend fun saveConversation(conversation: Conversation): AppResult<Unit>

    /**
     * Delete a conversation by ID.
     */
    suspend fun deleteConversation(id: String): AppResult<Unit>

    /**
     * Update a conversation using a transform function.
     * Returns the updated conversation.
     */
    suspend fun updateConversation(
        id: String,
        update: (Conversation) -> Conversation
    ): AppResult<Conversation>

    /**
     * Update the last message preview and timestamp.
     */
    suspend fun updateLastMessage(
        id: String,
        preview: String,
        timestamp: Long
    ): AppResult<Unit>

    /**
     * Update the relay cursor for pagination.
     */
    suspend fun updateCursor(id: String, cursor: String?): AppResult<Unit>

    /**
     * Mark a conversation as burned by peer.
     */
    suspend fun markPeerBurned(id: String, timestamp: Long): AppResult<Unit>

    /**
     * Update pad consumption after sending/receiving.
     */
    suspend fun updatePadConsumption(
        id: String,
        consumedFront: Long,
        consumedBack: Long
    ): AppResult<Unit>
}
