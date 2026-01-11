package com.monadial.ash

import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.entities.ConversationColor
import com.monadial.ash.domain.entities.ConversationRole
import com.monadial.ash.domain.entities.MessageRetention

/**
 * Test fixtures for unit tests.
 */
object TestFixtures {

    fun createConversation(
        id: String = "test-conversation-id",
        name: String? = "Test Conversation",
        relayUrl: String = "https://relay.test.com",
        authToken: String = "test-auth-token",
        burnToken: String = "test-burn-token",
        role: ConversationRole = ConversationRole.INITIATOR,
        color: ConversationColor = ConversationColor.INDIGO,
        createdAt: Long = System.currentTimeMillis(),
        padTotalSize: Long = 65536,
        padConsumedFront: Long = 0,
        padConsumedBack: Long = 0,
        peerBurnedAt: Long? = null,
        messageRetention: MessageRetention = MessageRetention.ONE_HOUR
    ): Conversation = Conversation(
        id = id,
        name = name,
        relayUrl = relayUrl,
        authToken = authToken,
        burnToken = burnToken,
        role = role,
        color = color,
        createdAt = createdAt,
        padTotalSize = padTotalSize,
        padConsumedFront = padConsumedFront,
        padConsumedBack = padConsumedBack,
        peerBurnedAt = peerBurnedAt,
        messageRetention = messageRetention
    )

    fun createMultipleConversations(count: Int): List<Conversation> {
        return (1..count).map { index ->
            createConversation(
                id = "conversation-$index",
                name = "Conversation $index"
            )
        }
    }
}
