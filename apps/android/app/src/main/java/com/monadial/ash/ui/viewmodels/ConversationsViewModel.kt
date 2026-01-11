package com.monadial.ash.ui.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.monadial.ash.core.common.AppResult
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.repositories.ConversationRepository
import com.monadial.ash.domain.repositories.PadRepository
import com.monadial.ash.domain.usecases.conversation.BurnConversationUseCase
import com.monadial.ash.domain.usecases.conversation.CheckBurnStatusUseCase
import com.monadial.ash.domain.usecases.conversation.GetConversationsUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * ViewModel for the conversations list screen.
 *
 * Follows Clean Architecture by:
 * - Using Use Cases for business logic (burn, check burn status)
 * - Using Repositories for data access
 * - Only handling UI state and user interactions
 */
@HiltViewModel
class ConversationsViewModel @Inject constructor(
    private val getConversationsUseCase: GetConversationsUseCase,
    private val burnConversationUseCase: BurnConversationUseCase,
    private val checkBurnStatusUseCase: CheckBurnStatusUseCase,
    private val conversationRepository: ConversationRepository,
    private val padRepository: PadRepository
) : ViewModel() {

    val conversations: StateFlow<List<Conversation>> = getConversationsUseCase.conversations

    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    init {
        loadConversations()
    }

    private fun loadConversations() {
        viewModelScope.launch {
            when (val result = getConversationsUseCase()) {
                is AppResult.Success -> _error.value = null
                is AppResult.Error -> _error.value = result.error.message
            }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _isRefreshing.value = true
            try {
                // Reload conversations
                getConversationsUseCase.refresh()

                // Check burn status for each conversation
                val currentConversations = conversations.value
                if (currentConversations.isNotEmpty()) {
                    checkBurnStatusUseCase.checkAll(currentConversations)
                }
            } finally {
                _isRefreshing.value = false
            }
        }
    }

    fun burnConversation(conversation: Conversation) {
        viewModelScope.launch {
            when (val result = burnConversationUseCase(conversation)) {
                is AppResult.Success -> {
                    // Successfully burned - list will auto-update via StateFlow
                }
                is AppResult.Error -> {
                    _error.value = "Failed to burn conversation: ${result.error.message}"
                }
            }
        }
    }

    fun deleteConversation(conversationId: String) {
        viewModelScope.launch {
            // Wipe pad bytes first (secure deletion)
            padRepository.wipePad(conversationId)
            // Then delete conversation record
            conversationRepository.deleteConversation(conversationId)
        }
    }

    fun clearError() {
        _error.value = null
    }
}
