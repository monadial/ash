package com.monadial.ash.domain.usecases.conversation

import com.monadial.ash.core.common.AppResult
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.repositories.ConversationRepository
import com.monadial.ash.domain.services.RelayService
import javax.inject.Inject

/**
 * Result of checking burn status.
 */
data class BurnStatusResult(
    val burned: Boolean,
    val burnedAt: String? = null,
    val conversationUpdated: Boolean = false
)

/**
 * Use case for checking if a conversation has been burned by the peer.
 *
 * This consolidates the check burn status logic from:
 * - ConversationsViewModel.checkBurnStatus()
 * - MessagingViewModel.checkBurnStatus()
 *
 * The check process:
 * 1. Queries relay server for burn status
 * 2. If burned and not already marked, updates local conversation state
 */
class CheckBurnStatusUseCase @Inject constructor(
    private val relayService: RelayService,
    private val conversationRepository: ConversationRepository
) {
    /**
     * Checks if a conversation has been burned by the peer.
     *
     * @param conversation The conversation to check
     * @param updateIfBurned If true, automatically updates local state when peer has burned
     * @return BurnStatusResult with burn status and whether local state was updated
     */
    suspend operator fun invoke(
        conversation: Conversation,
        updateIfBurned: Boolean = true
    ): AppResult<BurnStatusResult> {
        val result = relayService.checkBurnStatus(
            conversationId = conversation.id,
            authToken = conversation.authToken,
            relayUrl = conversation.relayUrl
        )

        return when (result) {
            is AppResult.Success -> {
                val status = result.data
                var conversationUpdated = false

                if (status.burned && conversation.peerBurnedAt == null && updateIfBurned) {
                    // Peer has burned - update local state
                    val updated = conversation.copy(peerBurnedAt = System.currentTimeMillis())
                    conversationRepository.saveConversation(updated)
                    conversationUpdated = true
                }

                AppResult.Success(
                    BurnStatusResult(
                        burned = status.burned,
                        burnedAt = status.burnedAt,
                        conversationUpdated = conversationUpdated
                    )
                )
            }
            is AppResult.Error -> {
                result
            }
        }
    }

    /**
     * Checks burn status for multiple conversations.
     *
     * @param conversations List of conversations to check
     * @return Map of conversation ID to burn status result
     */
    suspend fun checkAll(
        conversations: List<Conversation>
    ): Map<String, AppResult<BurnStatusResult>> {
        return conversations.associate { conversation ->
            conversation.id to invoke(conversation)
        }
    }
}
