package com.monadial.ash.ui.viewmodels

import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.monadial.ash.core.services.BiometricService
import com.monadial.ash.core.services.SettingsService
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

@HiltViewModel
class LockViewModel @Inject constructor(
    private val biometricService: BiometricService,
    private val settingsService: SettingsService
) : ViewModel() {
    private val _isUnlocked = MutableStateFlow(false)
    val isUnlocked: StateFlow<Boolean> = _isUnlocked.asStateFlow()

    private val _isBiometricAvailable = MutableStateFlow(false)
    val isBiometricAvailable: StateFlow<Boolean> = _isBiometricAvailable.asStateFlow()

    init {
        viewModelScope.launch {
            _isBiometricAvailable.value = biometricService.isAvailable &&
                settingsService.isBiometricEnabled.value

            // If biometric is not enabled, auto-unlock
            if (!settingsService.isBiometricEnabled.value) {
                _isUnlocked.value = true
            }
        }
    }

    fun authenticate(activity: FragmentActivity) {
        viewModelScope.launch {
            val success =
                biometricService.authenticate(
                    activity = activity,
                    title = "Unlock ASH",
                    subtitle = "Verify your identity to access secure messages"
                )
            if (success) {
                _isUnlocked.value = true
            }
        }
    }

    fun skipAuth() {
        _isUnlocked.value = true
    }
}
