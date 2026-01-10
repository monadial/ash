package com.monadial.ash.ui.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.monadial.ash.core.services.ConversationStorageService
import com.monadial.ash.core.services.RelayService
import com.monadial.ash.domain.entities.Conversation
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ConversationsViewModel @Inject constructor(
    private val conversationStorage: ConversationStorageService,
    private val relayService: RelayService
) : ViewModel() {

    val conversations: StateFlow<List<Conversation>> = conversationStorage.conversations

    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

    init {
        viewModelScope.launch {
            conversationStorage.loadConversations()
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _isRefreshing.value = true
            try {
                conversationStorage.loadConversations()

                // Check burn status for each conversation
                conversations.value.forEach { conv ->
                    checkBurnStatus(conv)
                }
            } finally {
                _isRefreshing.value = false
            }
        }
    }

    private suspend fun checkBurnStatus(conversation: Conversation) {
        val result = relayService.checkBurnStatus(
            conversationId = conversation.id,
            authToken = conversation.authToken,
            relayUrl = conversation.relayUrl
        )
        result.onSuccess { status ->
            if (status.burned && conversation.peerBurnedAt == null) {
                // Peer has burned - update local state
                val updated = conversation.copy(peerBurnedAt = System.currentTimeMillis())
                conversationStorage.saveConversation(updated)
            }
        }
    }

    fun burnConversation(conversation: Conversation) {
        viewModelScope.launch {
            // 1. Notify relay (fire-and-forget)
            try {
                relayService.burnConversation(
                    conversationId = conversation.id,
                    burnToken = conversation.burnToken,
                    relayUrl = conversation.relayUrl
                )
            } catch (_: Exception) {
                // Continue even if relay notification fails
            }

            // 2. Delete pad bytes (secure wipe)
            conversationStorage.deletePadBytes(conversation.id)

            // 3. Delete conversation record
            conversationStorage.deleteConversation(conversation.id)
        }
    }

    fun deleteConversation(conversationId: String) {
        viewModelScope.launch {
            conversationStorage.deleteConversation(conversationId)
            conversationStorage.deletePadBytes(conversationId)
        }
    }
}
