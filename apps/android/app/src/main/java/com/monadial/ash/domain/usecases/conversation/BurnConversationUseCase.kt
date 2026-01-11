package com.monadial.ash.domain.usecases.conversation

import com.monadial.ash.core.common.AppError
import com.monadial.ash.core.common.AppResult
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.repositories.ConversationRepository
import com.monadial.ash.domain.repositories.PadRepository
import com.monadial.ash.domain.services.RelayService
import javax.inject.Inject

/**
 * Use case for burning (permanently destroying) a conversation.
 *
 * This consolidates the burn logic from:
 * - ConversationsViewModel.burnConversation()
 * - ConversationInfoViewModel.burnConversation()
 * - SettingsViewModel.burnAllConversations() (per-conversation logic)
 *
 * The burn process:
 * 1. Notifies relay server (fire-and-forget - continue even if fails)
 * 2. Wipes pad bytes securely
 * 3. Deletes conversation record
 */
class BurnConversationUseCase @Inject constructor(
    private val relayService: RelayService,
    private val conversationRepository: ConversationRepository,
    private val padRepository: PadRepository
) {
    /**
     * Burns a conversation.
     *
     * @param conversation The conversation to burn
     * @return Success if local cleanup succeeded, Error only on critical failures
     */
    suspend operator fun invoke(conversation: Conversation): AppResult<Unit> {
        return try {
            // 1. Notify relay (fire-and-forget - continue even if fails)
            try {
                relayService.burnConversation(
                    conversationId = conversation.id,
                    burnToken = conversation.burnToken,
                    relayUrl = conversation.relayUrl
                )
            } catch (_: Exception) {
                // Continue even if relay notification fails
            }

            // 2. Wipe pad bytes securely
            padRepository.wipePad(conversation.id)

            // 3. Delete conversation record
            conversationRepository.deleteConversation(conversation.id)

            AppResult.Success(Unit)
        } catch (e: Exception) {
            AppResult.Error(AppError.Storage.WriteFailed("Failed to burn conversation", e))
        }
    }

    /**
     * Burns multiple conversations.
     *
     * @param conversations List of conversations to burn
     * @return Number of successfully burned conversations
     */
    suspend fun burnAll(conversations: List<Conversation>): Int {
        var burnedCount = 0
        conversations.forEach { conversation ->
            val result = invoke(conversation)
            if (result.isSuccess) {
                burnedCount++
            }
        }
        return burnedCount
    }
}
