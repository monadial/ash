package com.monadial.ash.core.services

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.monadial.ash.domain.entities.Conversation
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Pad storage data matching iOS PadStorageData structure.
 * Stores pad bytes together with consumption state for atomic persistence.
 */
@Serializable
data class PadStorageData(
    val bytes: String, // Base64-encoded pad bytes
    val consumedFront: Long,
    val consumedBack: Long
)

@Singleton
class ConversationStorageService @Inject constructor(@ApplicationContext private val context: Context) {
    private val masterKey =
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

    private val encryptedPrefs =
        EncryptedSharedPreferences.create(
            context,
            "ash_conversations",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )

    private val json = Json { ignoreUnknownKeys = true }

    private val _conversations = MutableStateFlow<List<Conversation>>(emptyList())
    val conversations: StateFlow<List<Conversation>> = _conversations.asStateFlow()

    suspend fun loadConversations() = withContext(Dispatchers.IO) {
        val all = encryptedPrefs.all
        val loaded =
            all.mapNotNull { (key, value) ->
                if (key.startsWith("conversation_") && value is String) {
                    try {
                        json.decodeFromString<Conversation>(value)
                    } catch (e: Exception) {
                        null
                    }
                } else {
                    null
                }
            }.sortedByDescending { it.lastMessageAt ?: it.createdAt }
        _conversations.value = loaded
    }

    suspend fun saveConversation(conversation: Conversation) = withContext(Dispatchers.IO) {
        val serialized = json.encodeToString(conversation)
        encryptedPrefs.edit()
            .putString("conversation_${conversation.id}", serialized)
            .apply()
        loadConversations()
    }

    suspend fun deleteConversation(conversationId: String) = withContext(Dispatchers.IO) {
        encryptedPrefs.edit()
            .remove("conversation_$conversationId")
            .apply()
        loadConversations()
    }

    suspend fun getConversation(conversationId: String): Conversation? = withContext(Dispatchers.IO) {
        val serialized = encryptedPrefs.getString("conversation_$conversationId", null)
        serialized?.let {
            try {
                json.decodeFromString<Conversation>(it)
            } catch (e: Exception) {
                null
            }
        }
    }

    // === Pad Storage (matching iOS PadStorageData) ===
    // Pad bytes and consumption state are stored together atomically

    /**
     * Save pad with initial state (after ceremony).
     * Matching iOS: PadManager.storePad
     */
    suspend fun savePadBytes(conversationId: String, padBytes: ByteArray) = withContext(Dispatchers.IO) {
        val storageData =
            PadStorageData(
                bytes = android.util.Base64.encodeToString(padBytes, android.util.Base64.NO_WRAP),
                consumedFront = 0,
                consumedBack = 0
            )
        val serialized = json.encodeToString(storageData)
        encryptedPrefs.edit()
            .putString("pad_$conversationId", serialized)
            .apply()
    }

    /**
     * Save pad with current consumption state.
     * Matching iOS: PadManager.savePadState
     */
    suspend fun savePadState(conversationId: String, padBytes: ByteArray, consumedFront: Long, consumedBack: Long) =
        withContext(Dispatchers.IO) {
            val storageData =
                PadStorageData(
                    bytes = android.util.Base64.encodeToString(padBytes, android.util.Base64.NO_WRAP),
                    consumedFront = consumedFront,
                    consumedBack = consumedBack
                )
            val serialized = json.encodeToString(storageData)
            encryptedPrefs.edit()
                .putString("pad_$conversationId", serialized)
                .apply()
        }

    /**
     * Get pad bytes only (for decryption/token derivation).
     */
    suspend fun getPadBytes(conversationId: String): ByteArray? = withContext(Dispatchers.IO) {
        val serialized = encryptedPrefs.getString("pad_$conversationId", null) ?: return@withContext null
        try {
            val storageData = json.decodeFromString<PadStorageData>(serialized)
            android.util.Base64.decode(storageData.bytes, android.util.Base64.NO_WRAP)
        } catch (e: Exception) {
            // Fallback: try legacy format (raw Base64)
            try {
                android.util.Base64.decode(serialized, android.util.Base64.NO_WRAP)
            } catch (e2: Exception) {
                null
            }
        }
    }

    /**
     * Get full pad storage data (bytes + consumption state).
     * Matching iOS: PadManager.loadPad reading from Keychain
     */
    suspend fun getPadStorageData(conversationId: String): PadStorageData? = withContext(Dispatchers.IO) {
        val serialized = encryptedPrefs.getString("pad_$conversationId", null) ?: return@withContext null
        try {
            json.decodeFromString<PadStorageData>(serialized)
        } catch (e: Exception) {
            // Fallback: try legacy format (raw Base64) - use conversation for state
            try {
                val bytes = android.util.Base64.decode(serialized, android.util.Base64.NO_WRAP)
                val conversation = getConversation(conversationId)
                PadStorageData(
                    bytes = android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP),
                    consumedFront = conversation?.padConsumedFront ?: 0,
                    consumedBack = conversation?.padConsumedBack ?: 0
                )
            } catch (e2: Exception) {
                null
            }
        }
    }

    suspend fun deletePadBytes(conversationId: String) = withContext(Dispatchers.IO) {
        encryptedPrefs.edit()
            .remove("pad_$conversationId")
            .apply()
    }

    /**
     * Update consumption state in pad storage.
     * Matching iOS: PadManager.savePadState
     */
    suspend fun updatePadConsumption(conversationId: String, consumedFront: Long, consumedBack: Long) =
        withContext(Dispatchers.IO) {
            // Load existing pad data
            val existing = getPadStorageData(conversationId) ?: return@withContext

            // Save with updated consumption state
            val updated =
                existing.copy(
                    consumedFront = consumedFront,
                    consumedBack = consumedBack
                )
            val serialized = json.encodeToString(updated)
            encryptedPrefs.edit()
                .putString("pad_$conversationId", serialized)
                .apply()
        }
}
