package com.monadial.ash.ui.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.monadial.ash.core.services.SettingsService
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

@HiltViewModel
class AppViewModel @Inject constructor(private val settingsService: SettingsService) : ViewModel() {
    private val _isLocked = MutableStateFlow(true)
    val isLocked: StateFlow<Boolean> = _isLocked.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    init {
        viewModelScope.launch {
            settingsService.isBiometricEnabled.collect { enabled ->
                if (!enabled) {
                    _isLocked.value = false
                }
                _isLoading.value = false
            }
        }

        // Listen for background lock trigger
        viewModelScope.launch {
            settingsService.shouldLock.collect { shouldLock ->
                if (shouldLock) {
                    val biometricEnabled = settingsService.isBiometricEnabled.value
                    if (biometricEnabled) {
                        _isLocked.value = true
                    }
                    settingsService.clearLock()
                }
            }
        }
    }

    fun unlock() {
        _isLocked.value = false
    }

    fun lock() {
        viewModelScope.launch {
            if (settingsService.isBiometricEnabled.value) {
                _isLocked.value = true
            }
        }
    }
}
