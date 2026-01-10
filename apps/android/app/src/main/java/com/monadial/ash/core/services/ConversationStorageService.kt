package com.monadial.ash.core.services

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.monadial.ash.domain.entities.Conversation
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ConversationStorageService @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val encryptedPrefs = EncryptedSharedPreferences.create(
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
        val loaded = all.mapNotNull { (key, value) ->
            if (key.startsWith("conversation_") && value is String) {
                try {
                    json.decodeFromString<Conversation>(value)
                } catch (e: Exception) {
                    null
                }
            } else null
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

    // Store pad bytes separately for security
    suspend fun savePadBytes(conversationId: String, padBytes: ByteArray) = withContext(Dispatchers.IO) {
        val encoded = android.util.Base64.encodeToString(padBytes, android.util.Base64.NO_WRAP)
        encryptedPrefs.edit()
            .putString("pad_$conversationId", encoded)
            .apply()
    }

    suspend fun getPadBytes(conversationId: String): ByteArray? = withContext(Dispatchers.IO) {
        val encoded = encryptedPrefs.getString("pad_$conversationId", null)
        encoded?.let {
            try {
                android.util.Base64.decode(it, android.util.Base64.NO_WRAP)
            } catch (e: Exception) {
                null
            }
        }
    }

    suspend fun deletePadBytes(conversationId: String) = withContext(Dispatchers.IO) {
        encryptedPrefs.edit()
            .remove("pad_$conversationId")
            .apply()
    }

    suspend fun updatePadConsumption(
        conversationId: String,
        padConsumedFront: Long,
        padConsumedBack: Long
    ) = withContext(Dispatchers.IO) {
        val conversation = getConversation(conversationId) ?: return@withContext
        val updated = conversation.copy(
            padConsumedFront = padConsumedFront,
            padConsumedBack = padConsumedBack
        )
        saveConversation(updated)
    }
}
