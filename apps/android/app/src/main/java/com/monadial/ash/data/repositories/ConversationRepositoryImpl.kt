package com.monadial.ash.data.repositories

import com.monadial.ash.core.common.AppError
import com.monadial.ash.core.common.AppResult
import com.monadial.ash.core.services.ConversationStorageService
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.repositories.ConversationRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.StateFlow

/**
 * Implementation of ConversationRepository using ConversationStorageService.
 * Provides a clean interface for conversation data operations.
 */
@Singleton
class ConversationRepositoryImpl @Inject constructor(
    private val storageService: ConversationStorageService
) : ConversationRepository {

    override val conversations: StateFlow<List<Conversation>>
        get() = storageService.conversations

    override suspend fun loadConversations(): AppResult<List<Conversation>> {
        return try {
            storageService.loadConversations()
            AppResult.Success(storageService.conversations.value)
        } catch (e: Exception) {
            AppResult.Error(AppError.Storage.ReadFailed("Failed to load conversations", e))
        }
    }

    override suspend fun getConversation(id: String): AppResult<Conversation> {
        return try {
            val conversation = storageService.getConversation(id)
            if (conversation != null) {
                AppResult.Success(conversation)
            } else {
                AppResult.Error(AppError.Storage.NotFound("Conversation not found: $id"))
            }
        } catch (e: Exception) {
            AppResult.Error(AppError.Storage.ReadFailed("Failed to get conversation", e))
        }
    }

    override suspend fun saveConversation(conversation: Conversation): AppResult<Unit> {
        return try {
            storageService.saveConversation(conversation)
            AppResult.Success(Unit)
        } catch (e: Exception) {
            AppResult.Error(AppError.Storage.WriteFailed("Failed to save conversation", e))
        }
    }

    override suspend fun deleteConversation(id: String): AppResult<Unit> {
        return try {
            storageService.deleteConversation(id)
            AppResult.Success(Unit)
        } catch (e: Exception) {
            AppResult.Error(AppError.Storage.WriteFailed("Failed to delete conversation", e))
        }
    }

    override suspend fun updateConversation(
        id: String,
        update: (Conversation) -> Conversation
    ): AppResult<Conversation> {
        return try {
            val existing = storageService.getConversation(id)
                ?: return AppResult.Error(AppError.Storage.NotFound("Conversation not found: $id"))

            val updated = update(existing)
            storageService.saveConversation(updated)
            AppResult.Success(updated)
        } catch (e: Exception) {
            AppResult.Error(AppError.Storage.WriteFailed("Failed to update conversation", e))
        }
    }

    override suspend fun updateLastMessage(
        id: String,
        preview: String,
        timestamp: Long
    ): AppResult<Unit> {
        return updateConversation(id) { conversation ->
            conversation.copy(
                lastMessagePreview = preview,
                lastMessageAt = timestamp
            )
        }.map { }
    }

    override suspend fun updateCursor(id: String, cursor: String?): AppResult<Unit> {
        return updateConversation(id) { conversation ->
            conversation.withCursor(cursor)
        }.map { }
    }

    override suspend fun markPeerBurned(id: String, timestamp: Long): AppResult<Unit> {
        return updateConversation(id) { conversation ->
            conversation.copy(peerBurnedAt = timestamp)
        }.map { }
    }

    override suspend fun updatePadConsumption(
        id: String,
        consumedFront: Long,
        consumedBack: Long
    ): AppResult<Unit> {
        return updateConversation(id) { conversation ->
            conversation.copy(
                padConsumedFront = consumedFront,
                padConsumedBack = consumedBack
            )
        }.map { }
    }
}
