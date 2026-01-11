package com.monadial.ash.domain.repositories

import com.monadial.ash.core.common.AppResult
import com.monadial.ash.core.services.PadState
import com.monadial.ash.domain.entities.ConversationRole

/**
 * Repository interface for pad (one-time pad) operations.
 * Wraps the PadManager to provide a clean interface for the domain layer.
 */
interface PadRepository {

    /**
     * Store pad bytes for a new conversation (after ceremony).
     */
    suspend fun storePad(conversationId: String, padBytes: ByteArray): AppResult<Unit>

    /**
     * Get the raw pad bytes for a conversation.
     */
    suspend fun getPadBytes(conversationId: String): AppResult<ByteArray>

    /**
     * Get the current pad state (for UI display).
     */
    suspend fun getPadState(conversationId: String): AppResult<PadState>

    /**
     * Check if a message of given length can be sent.
     */
    suspend fun canSend(conversationId: String, length: Int, role: ConversationRole): AppResult<Boolean>

    /**
     * Get the number of bytes available for sending.
     */
    suspend fun availableForSending(conversationId: String, role: ConversationRole): AppResult<Long>

    /**
     * Get the next send offset (sequence number for message).
     */
    suspend fun nextSendOffset(conversationId: String, role: ConversationRole): AppResult<Long>

    /**
     * Consume pad bytes for sending a message.
     * Returns the key bytes for encryption.
     *
     * IMPORTANT: This updates consumption state - call only once per message!
     */
    suspend fun consumeForSending(
        conversationId: String,
        length: Int,
        role: ConversationRole
    ): AppResult<ByteArray>

    /**
     * Get pad bytes for decryption at a specific offset.
     * Does NOT update consumption state.
     */
    suspend fun getBytesForDecryption(
        conversationId: String,
        offset: Long,
        length: Int
    ): AppResult<ByteArray>

    /**
     * Update peer's consumption based on received message.
     */
    suspend fun updatePeerConsumption(
        conversationId: String,
        peerRole: ConversationRole,
        consumed: Long
    ): AppResult<Unit>

    /**
     * Zero pad bytes at specific offset (for forward secrecy).
     * When a message expires, the key material is zeroed to prevent future decryption.
     */
    suspend fun zeroPadBytes(
        conversationId: String,
        offset: Long,
        length: Int
    ): AppResult<Unit>

    /**
     * Securely wipe pad for a conversation.
     */
    suspend fun wipePad(conversationId: String): AppResult<Unit>

    /**
     * Invalidate cached pad (call when conversation is deleted).
     */
    fun invalidateCache(conversationId: String)

    /**
     * Clear all cached pads.
     */
    fun clearCache()
}
