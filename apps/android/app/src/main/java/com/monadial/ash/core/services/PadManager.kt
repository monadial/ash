package com.monadial.ash.core.services

import android.util.Log
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import uniffi.ash.Pad
import uniffi.ash.Role
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Pad state for UI display
 */
data class PadState(
    val totalBytes: Long,
    val consumedFront: Long,
    val consumedBack: Long,
    val remaining: Long,
    val isExhausted: Boolean
)

/**
 * PadManager - Manages pad state using Rust core for allocation logic
 *
 * This service wraps the Rust Pad implementation to ensure iOS and Android
 * use identical pad allocation logic. All pad operations go through this service.
 *
 * Matching iOS: apps/ios/Ash/Ash/Core/Services/PadManager.swift
 */
@Singleton
class PadManager @Inject constructor(
    private val conversationStorage: ConversationStorageService
) {
    companion object {
        private const val TAG = "PadManager"
    }

    // Mutex for thread-safe access (replaces @Synchronized for suspend functions)
    private val mutex = Mutex()

    // In-memory cache of loaded pads (Rust Pad objects)
    private val padCache = mutableMapOf<String, Pad>()

    // MARK: - Load/Store

    /**
     * Load pad for a conversation, using cache if available
     */
    suspend fun loadPad(conversationId: String): Pad = mutex.withLock {
        // Check cache first
        padCache[conversationId]?.let { return@withLock it }

        // Load from storage
        val padBytes = conversationStorage.getPadBytes(conversationId)
            ?: throw IllegalStateException("Pad not found for conversation $conversationId")

        val conversation = conversationStorage.getConversation(conversationId)
            ?: throw IllegalStateException("Conversation not found: $conversationId")

        // Create Rust Pad with state
        val pad = Pad.fromBytesWithState(
            padBytes.map { it.toUByte() },
            conversation.padConsumedFront.toULong(),
            conversation.padConsumedBack.toULong()
        )

        padCache[conversationId] = pad
        pad
    }

    /**
     * Store pad bytes for a new conversation (after ceremony)
     */
    suspend fun storePad(bytes: ByteArray, conversationId: String) = mutex.withLock {
        conversationStorage.savePadBytes(conversationId, bytes)

        // Create and cache the Rust Pad
        val pad = Pad.fromBytes(bytes.map { it.toUByte() })
        padCache[conversationId] = pad
    }

    /**
     * Save current pad state to storage
     * Note: Called within mutex.withLock, no additional locking needed
     */
    private suspend fun savePadState(pad: Pad, conversationId: String) {
        val consumedFront = pad.consumedFront().toLong()
        val consumedBack = pad.consumedBack().toLong()
        conversationStorage.updatePadConsumption(conversationId, consumedFront, consumedBack)
    }

    // MARK: - Send Operations

    /**
     * Check if a message of given length can be sent
     */
    suspend fun canSend(length: Int, role: Role, conversationId: String): Boolean {
        val pad = loadPad(conversationId)
        return pad.canSend(length.toUInt(), role)
    }

    /**
     * Get bytes available for sending
     */
    suspend fun availableForSending(role: Role, conversationId: String): Long {
        val pad = loadPad(conversationId)
        return pad.availableForSending(role).toLong()
    }

    /**
     * Get the next send offset (for message sequencing)
     */
    suspend fun nextSendOffset(role: Role, conversationId: String): Long {
        val pad = loadPad(conversationId)
        return pad.nextSendOffset(role).toLong()
    }

    /**
     * Consume pad bytes for sending a message.
     * Returns the key bytes for encryption.
     *
     * IMPORTANT: This updates consumption state - call only once per message!
     */
    suspend fun consumeForSending(length: Int, role: Role, conversationId: String): ByteArray = mutex.withLock {
        // Get cached pad or load it
        val pad = padCache[conversationId] ?: run {
            val padBytes = conversationStorage.getPadBytes(conversationId)
                ?: throw IllegalStateException("Pad not found for conversation $conversationId")
            val conversation = conversationStorage.getConversation(conversationId)
                ?: throw IllegalStateException("Conversation not found: $conversationId")
            Pad.fromBytesWithState(
                padBytes.map { it.toUByte() },
                conversation.padConsumedFront.toULong(),
                conversation.padConsumedBack.toULong()
            ).also { padCache[conversationId] = it }
        }

        Log.d(TAG, "Consuming $length bytes for sending (role=$role, conv=${conversationId.take(8)})")

        // Consume bytes using Rust Pad
        val keyBytes = pad.consume(length.toUInt(), role)

        // Persist updated state
        savePadState(pad, conversationId)

        Log.d(TAG, "Consumption complete. Front=${pad.consumedFront()}, Back=${pad.consumedBack()}")

        keyBytes.map { it.toByte() }.toByteArray()
    }

    // MARK: - Receive Operations

    /**
     * Update peer's consumption based on received message
     */
    suspend fun updatePeerConsumption(peerRole: Role, consumed: Long, conversationId: String) = mutex.withLock {
        // Get cached pad or load it
        val pad = padCache[conversationId] ?: run {
            val padBytes = conversationStorage.getPadBytes(conversationId)
                ?: throw IllegalStateException("Pad not found for conversation $conversationId")
            val conversation = conversationStorage.getConversation(conversationId)
                ?: throw IllegalStateException("Conversation not found: $conversationId")
            Pad.fromBytesWithState(
                padBytes.map { it.toUByte() },
                conversation.padConsumedFront.toULong(),
                conversation.padConsumedBack.toULong()
            ).also { padCache[conversationId] = it }
        }

        pad.updatePeerConsumption(peerRole, consumed.toULong())

        // Persist updated state
        savePadState(pad, conversationId)

        Log.d(TAG, "Updated peer consumption. Front=${pad.consumedFront()}, Back=${pad.consumedBack()}")
    }

    /**
     * Get pad bytes for decryption at a specific offset
     */
    suspend fun getBytesForDecryption(offset: Long, length: Int, conversationId: String): ByteArray {
        val pad = loadPad(conversationId)
        val bytes = pad.asBytes()

        val start = offset.toInt()
        val end = minOf(start + length, bytes.size)

        if (start < 0 || end > bytes.size || start >= end) {
            throw IllegalStateException("Invalid pad range: offset=$offset, length=$length, padSize=${bytes.size}")
        }

        return bytes.subList(start, end).map { it.toByte() }.toByteArray()
    }

    // MARK: - State Queries

    /**
     * Get current pad state (for UI display)
     */
    suspend fun getPadState(conversationId: String): PadState {
        val pad = loadPad(conversationId)
        return PadState(
            totalBytes = pad.totalSize().toLong(),
            consumedFront = pad.consumedFront().toLong(),
            consumedBack = pad.consumedBack().toLong(),
            remaining = pad.remaining().toLong(),
            isExhausted = pad.isExhausted()
        )
    }

    // MARK: - Forward Secrecy

    /**
     * Zero pad bytes at specific offset (for forward secrecy).
     * When a message expires, the key material is zeroed to prevent future decryption.
     */
    suspend fun zeroPadBytes(offset: Long, length: Int, conversationId: String) = mutex.withLock {
        // Get cached pad or load it
        val pad = padCache[conversationId] ?: run {
            val padBytes = conversationStorage.getPadBytes(conversationId)
                ?: throw IllegalStateException("Pad not found for conversation $conversationId")
            val conversation = conversationStorage.getConversation(conversationId)
                ?: throw IllegalStateException("Conversation not found: $conversationId")
            Pad.fromBytesWithState(
                padBytes.map { it.toUByte() },
                conversation.padConsumedFront.toULong(),
                conversation.padConsumedBack.toULong()
            ).also { padCache[conversationId] = it }
        }

        val success = pad.zeroBytesAt(offset.toULong(), length.toULong())

        if (success) {
            // Persist updated state (with zeroed bytes)
            // Note: We need to save the full pad bytes, not just consumption state
            val bytes = pad.asBytes().map { it.toByte() }.toByteArray()
            conversationStorage.savePadBytes(conversationId, bytes)
            Log.d(TAG, "Zeroed $length pad bytes at offset $offset for forward secrecy")
        } else {
            Log.w(TAG, "Failed to zero pad bytes: offset $offset, length $length out of bounds")
        }
    }

    // MARK: - Cleanup

    /**
     * Wipe pad for a conversation
     */
    suspend fun wipePad(conversationId: String) = mutex.withLock {
        padCache.remove(conversationId)
        conversationStorage.deletePadBytes(conversationId)
    }

    /**
     * Get pad bytes (for token derivation before wiping)
     */
    suspend fun getPadBytes(conversationId: String): ByteArray {
        val pad = loadPad(conversationId)
        return pad.asBytes().map { it.toByte() }.toByteArray()
    }

    /**
     * Invalidate cached pad (call when conversation is deleted)
     */
    @Synchronized
    fun invalidateCache(conversationId: String) {
        padCache.remove(conversationId)
    }

    /**
     * Clear all cached pads
     */
    @Synchronized
    fun clearCache() {
        padCache.clear()
    }
}
