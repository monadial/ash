package com.monadial.ash.ui.viewmodels

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.monadial.ash.core.services.ConversationStorageService
import com.monadial.ash.core.services.RelayService
import com.monadial.ash.domain.entities.Conversation
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

@HiltViewModel
class ConversationInfoViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val conversationStorage: ConversationStorageService,
    private val relayService: RelayService
) : ViewModel() {
    private val conversationId: String = savedStateHandle["conversationId"]!!

    private val _conversation = MutableStateFlow<Conversation?>(null)
    val conversation: StateFlow<Conversation?> = _conversation.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isBurning = MutableStateFlow(false)
    val isBurning: StateFlow<Boolean> = _isBurning.asStateFlow()

    private val _burned = MutableStateFlow(false)
    val burned: StateFlow<Boolean> = _burned.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    init {
        loadConversation()
    }

    private fun loadConversation() {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                _conversation.value = conversationStorage.getConversation(conversationId)
            } catch (e: Exception) {
                _error.value = "Failed to load conversation: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun renameConversation(newName: String?) {
        val conv = _conversation.value ?: return
        viewModelScope.launch {
            try {
                val updated = conv.renamed(newName)
                conversationStorage.saveConversation(updated)
                _conversation.value = updated
            } catch (e: Exception) {
                _error.value = "Failed to rename: ${e.message}"
            }
        }
    }

    fun burnConversation() {
        val conv = _conversation.value ?: return
        viewModelScope.launch {
            _isBurning.value = true
            try {
                // 1. Notify relay (fire-and-forget)
                relayService.burnConversation(
                    conversationId = conv.id,
                    burnToken = conv.burnToken,
                    relayUrl = conv.relayUrl
                )

                // 2. Wipe pad bytes locally
                conversationStorage.deletePadBytes(conv.id)

                // 3. Delete conversation record
                conversationStorage.deleteConversation(conv.id)

                _burned.value = true
            } catch (e: Exception) {
                _error.value = "Failed to burn: ${e.message}"
            } finally {
                _isBurning.value = false
            }
        }
    }

    fun clearError() {
        _error.value = null
    }
}
