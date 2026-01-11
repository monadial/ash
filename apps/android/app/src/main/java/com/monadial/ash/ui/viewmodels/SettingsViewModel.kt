package com.monadial.ash.ui.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.monadial.ash.BuildConfig
import com.monadial.ash.core.services.ConnectionTestResult
import com.monadial.ash.core.services.ConversationStorageService
import com.monadial.ash.core.services.RelayService
import com.monadial.ash.core.services.SettingsService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settingsService: SettingsService,
    private val conversationStorage: ConversationStorageService,
    private val relayService: RelayService
) : ViewModel() {

    val isBiometricEnabled: StateFlow<Boolean> = settingsService.isBiometricEnabled

    private val _lockOnBackground = MutableStateFlow(true)
    val lockOnBackground: StateFlow<Boolean> = _lockOnBackground.asStateFlow()

    // Saved relay URL (from settings)
    private val _relayUrl = MutableStateFlow("")
    val relayUrl: StateFlow<String> = _relayUrl.asStateFlow()

    // Edited relay URL (for UI editing)
    private val _editedRelayUrl = MutableStateFlow("")
    val editedRelayUrl: StateFlow<String> = _editedRelayUrl.asStateFlow()

    // Track if there are unsaved changes
    private val _hasUnsavedChanges = MutableStateFlow(false)
    val hasUnsavedChanges: StateFlow<Boolean> = _hasUnsavedChanges.asStateFlow()

    private val _isTestingConnection = MutableStateFlow(false)
    val isTestingConnection: StateFlow<Boolean> = _isTestingConnection.asStateFlow()

    private val _connectionTestResult = MutableStateFlow<ConnectionTestResult?>(null)
    val connectionTestResult: StateFlow<ConnectionTestResult?> = _connectionTestResult.asStateFlow()

    private val _isBurningAll = MutableStateFlow(false)
    val isBurningAll: StateFlow<Boolean> = _isBurningAll.asStateFlow()

    init {
        viewModelScope.launch {
            settingsService.lockOnBackground.collect {
                _lockOnBackground.value = it
            }
        }
        viewModelScope.launch {
            settingsService.relayServerUrl.collect { url ->
                _relayUrl.value = url
                // Only update edited URL if there are no unsaved changes
                if (!_hasUnsavedChanges.value) {
                    _editedRelayUrl.value = url
                }
            }
        }
        // Track unsaved changes
        viewModelScope.launch {
            combine(_relayUrl, _editedRelayUrl) { saved, edited ->
                saved != edited
            }.collect {
                _hasUnsavedChanges.value = it
            }
        }
    }

    fun setEditedRelayUrl(url: String) {
        _editedRelayUrl.value = url
        // Clear test result when URL changes
        _connectionTestResult.value = null
    }

    fun saveRelayUrl() {
        viewModelScope.launch {
            settingsService.setRelayServerUrl(_editedRelayUrl.value)
        }
    }

    fun resetRelayUrl() {
        _editedRelayUrl.value = BuildConfig.DEFAULT_RELAY_URL
        _connectionTestResult.value = null
    }

    fun discardChanges() {
        _editedRelayUrl.value = _relayUrl.value
        _connectionTestResult.value = null
    }

    fun setBiometricEnabled(enabled: Boolean) {
        viewModelScope.launch {
            settingsService.setBiometricEnabled(enabled)
        }
    }

    fun setLockOnBackground(enabled: Boolean) {
        viewModelScope.launch {
            settingsService.setLockOnBackground(enabled)
        }
    }

    fun testConnection() {
        viewModelScope.launch {
            _isTestingConnection.value = true
            _connectionTestResult.value = null
            try {
                // Use the edited URL for testing (allows testing before saving)
                val url = _editedRelayUrl.value
                val result = relayService.testConnection(url)
                _connectionTestResult.value = result
            } catch (e: Exception) {
                _connectionTestResult.value = ConnectionTestResult(
                    success = false,
                    error = e.message
                )
            } finally {
                _isTestingConnection.value = false
            }
        }
    }

    fun burnAllConversations() {
        viewModelScope.launch {
            _isBurningAll.value = true
            try {
                val conversations = conversationStorage.conversations.value

                // Burn each conversation
                for (conv in conversations) {
                    // Notify relay (fire-and-forget)
                    try {
                        relayService.burnConversation(
                            conversationId = conv.id,
                            burnToken = conv.burnToken,
                            relayUrl = conv.relayUrl
                        )
                    } catch (_: Exception) {
                        // Continue even if relay notification fails
                    }

                    // Delete pad bytes
                    conversationStorage.deletePadBytes(conv.id)

                    // Delete conversation
                    conversationStorage.deleteConversation(conv.id)
                }

                // Reload conversations to update state
                conversationStorage.loadConversations()
            } finally {
                _isBurningAll.value = false
            }
        }
    }
}
