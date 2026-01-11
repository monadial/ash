package com.monadial.ash.ui.viewmodels

import android.graphics.Bitmap
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.monadial.ash.core.services.AshCoreService
import com.monadial.ash.core.services.ConversationStorageService
import com.monadial.ash.core.services.PadManager
import com.monadial.ash.core.services.QRCodeService
import com.monadial.ash.core.services.RelayService
import com.monadial.ash.core.services.SettingsService
import com.monadial.ash.domain.entities.CeremonyError
import com.monadial.ash.domain.entities.CeremonyPhase
import com.monadial.ash.domain.entities.ConsentState
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.entities.ConversationColor
import com.monadial.ash.domain.entities.ConversationRole
import com.monadial.ash.domain.entities.DisappearingMessages
import com.monadial.ash.domain.entities.MessageRetention
import com.monadial.ash.domain.entities.PadSize
import dagger.hilt.android.lifecycle.HiltViewModel
import java.security.SecureRandom
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.ash.CeremonyMetadata
import uniffi.ash.FountainFrameGenerator

@HiltViewModel
class InitiatorCeremonyViewModel @Inject constructor(
    private val settingsService: SettingsService,
    private val qrCodeService: QRCodeService,
    private val conversationStorage: ConversationStorageService,
    private val relayService: RelayService,
    private val ashCoreService: AshCoreService,
    private val padManager: PadManager
) : ViewModel() {
    // Note: relayService is already injected, used for connection testing and conversation registration

    companion object {
        private const val TAG = "InitiatorCeremonyVM"

        // Block size for fountain encoding (1500 bytes + 16 header, base64 ~2021 chars, fits Version 23-24 QR)
        // Must match iOS: apps/ios/Ash/Ash/Presentation/ViewModels/InitiatorCeremonyViewModel.swift
        private const val FOUNTAIN_BLOCK_SIZE = 1500u

        // QR code size in pixels (larger for better scanning)
        private const val QR_CODE_SIZE = 600

        // Frame display interval in milliseconds (matches iOS 0.15s = 150ms, ~6.67 FPS)
        private const val FRAME_DISPLAY_INTERVAL_MS = 150L
    }

    // State
    private val _phase = MutableStateFlow<CeremonyPhase>(CeremonyPhase.SelectingPadSize)
    val phase: StateFlow<CeremonyPhase> = _phase.asStateFlow()

    private val _selectedPadSize = MutableStateFlow(PadSize.MEDIUM)
    val selectedPadSize: StateFlow<PadSize> = _selectedPadSize.asStateFlow()

    private val _selectedColor = MutableStateFlow(ConversationColor.INDIGO)
    val selectedColor: StateFlow<ConversationColor> = _selectedColor.asStateFlow()

    private val _conversationName = MutableStateFlow("")
    val conversationName: StateFlow<String> = _conversationName.asStateFlow()

    private val _relayUrl = MutableStateFlow("")
    val relayUrl: StateFlow<String> = _relayUrl.asStateFlow()

    private val _serverRetention = MutableStateFlow(MessageRetention.ONE_DAY)
    val serverRetention: StateFlow<MessageRetention> = _serverRetention.asStateFlow()

    private val _disappearingMessages = MutableStateFlow(DisappearingMessages.OFF)
    val disappearingMessages: StateFlow<DisappearingMessages> = _disappearingMessages.asStateFlow()

    private val _consent = MutableStateFlow(ConsentState())
    val consent: StateFlow<ConsentState> = _consent.asStateFlow()

    private val _entropyProgress = MutableStateFlow(0f)
    val entropyProgress: StateFlow<Float> = _entropyProgress.asStateFlow()

    private val _currentQRBitmap = MutableStateFlow<Bitmap?>(null)
    val currentQRBitmap: StateFlow<Bitmap?> = _currentQRBitmap.asStateFlow()

    private val _currentFrameIndex = MutableStateFlow(0)
    val currentFrameIndex: StateFlow<Int> = _currentFrameIndex.asStateFlow()

    private val _totalFrames = MutableStateFlow(0)
    val totalFrames: StateFlow<Int> = _totalFrames.asStateFlow()

    private val _connectionTestResult = MutableStateFlow<ConnectionTestResult?>(null)
    val connectionTestResult: StateFlow<ConnectionTestResult?> = _connectionTestResult.asStateFlow()

    private val _isTestingConnection = MutableStateFlow(false)
    val isTestingConnection: StateFlow<Boolean> = _isTestingConnection.asStateFlow()

    // Passphrase protection
    private val _passphraseEnabled = MutableStateFlow(false)
    val passphraseEnabled: StateFlow<Boolean> = _passphraseEnabled.asStateFlow()

    private val _passphrase = MutableStateFlow("")
    val passphrase: StateFlow<String> = _passphrase.asStateFlow()

    // Playback controls
    private val _isPaused = MutableStateFlow(false)
    val isPaused: StateFlow<Boolean> = _isPaused.asStateFlow()

    private val _fps = MutableStateFlow(7) // Default ~7 FPS (150ms interval, matches iOS)
    val fps: StateFlow<Int> = _fps.asStateFlow()

    // Private state
    private val collectedEntropy = mutableListOf<Byte>()
    private var generatedPadBytes: ByteArray? = null
    private var preGeneratedQRImages: List<Bitmap> = emptyList()
    private var displayJob: Job? = null
    private var mnemonic: List<String> = emptyList()
    private var fountainGenerator: FountainFrameGenerator? = null
    private var isGeneratingPad: Boolean = false // Guard against multiple generatePad() calls

    sealed class ConnectionTestResult {
        data class Success(val version: String) : ConnectionTestResult()

        data class Failure(val error: String) : ConnectionTestResult()
    }

    init {
        viewModelScope.launch {
            _relayUrl.value = settingsService.getRelayUrl()
        }
    }

    // MARK: - Pad Size Selection

    fun selectPadSize(size: PadSize) {
        _selectedPadSize.value = size
    }

    fun setPassphraseEnabled(enabled: Boolean) {
        _passphraseEnabled.value = enabled
        if (!enabled) {
            _passphrase.value = ""
        }
    }

    fun setPassphrase(value: String) {
        _passphrase.value = value
    }

    fun proceedToOptions() {
        _phase.value = CeremonyPhase.ConfiguringOptions
    }

    // MARK: - Options Configuration

    fun setConversationName(name: String) {
        _conversationName.value = name
    }

    fun setRelayUrl(url: String) {
        _relayUrl.value = url
        _connectionTestResult.value = null
    }

    fun setSelectedColor(color: ConversationColor) {
        _selectedColor.value = color
    }

    fun setServerRetention(retention: MessageRetention) {
        _serverRetention.value = retention
    }

    fun setDisappearingMessages(setting: DisappearingMessages) {
        _disappearingMessages.value = setting
    }

    fun testRelayConnection() {
        viewModelScope.launch {
            _isTestingConnection.value = true
            _connectionTestResult.value = null
            try {
                val result = relayService.testConnection(_relayUrl.value)
                _connectionTestResult.value =
                    if (result.success) {
                        ConnectionTestResult.Success(result.version ?: "OK")
                    } else {
                        ConnectionTestResult.Failure(result.error ?: "Connection failed")
                    }
            } catch (e: Exception) {
                _connectionTestResult.value = ConnectionTestResult.Failure(e.message ?: "Unknown error")
            } finally {
                _isTestingConnection.value = false
            }
        }
    }

    fun proceedToConsent() {
        _phase.value = CeremonyPhase.ConfirmingConsent
    }

    // MARK: - Consent

    fun updateConsent(consent: ConsentState) {
        _consent.value = consent
    }

    fun confirmConsent() {
        if (_consent.value.allConfirmed) {
            _phase.value = CeremonyPhase.CollectingEntropy
        }
    }

    // MARK: - Entropy Collection

    fun addEntropy(x: Float, y: Float) {
        // Don't collect more entropy once we've started generating the pad
        if (isGeneratingPad) return

        val timestamp = System.currentTimeMillis()
        val nanoTime = System.nanoTime()

        // Collect more data per touch point for stronger entropy
        collectedEntropy.add((x * 256).toInt().toByte())
        collectedEntropy.add((y * 256).toInt().toByte())
        collectedEntropy.add((timestamp and 0xFF).toByte())
        collectedEntropy.add(((timestamp shr 8) and 0xFF).toByte())
        collectedEntropy.add((nanoTime and 0xFF).toByte())

        // Require 750 bytes of entropy (~150 touch points with 5 bytes each)
        _entropyProgress.value = minOf(1f, collectedEntropy.size / 750f)

        if (_entropyProgress.value >= 1f && !isGeneratingPad) {
            isGeneratingPad = true
            generatePad()
        }
    }

    // MARK: - Pad Generation

    private fun generatePad() {
        // Take a snapshot of entropy immediately to avoid ConcurrentModificationException
        val entropySnapshot = collectedEntropy.toList()
        val padSize = _selectedPadSize.value.bytes.toInt()

        viewModelScope.launch {
            _phase.value = CeremonyPhase.GeneratingPad

            try {
                val padBytes =
                    withContext(Dispatchers.Default) {
                        generatePadBytes(
                            entropy = entropySnapshot.toByteArray(),
                            sizeBytes = padSize
                        )
                    }
                generatedPadBytes = padBytes

                Log.d(TAG, "Generated pad: ${padBytes.size} bytes")

                // Log first and last 16 bytes for debugging cross-platform
                val firstBytes = padBytes.take(16).joinToString("") { String.format("%02X", it) }
                val lastBytes = padBytes.takeLast(16).joinToString("") { String.format("%02X", it) }
                Log.d(TAG, "Pad first 16 bytes: $firstBytes")
                Log.d(TAG, "Pad last 16 bytes: $lastBytes")

                // Generate mnemonic from pad using FFI
                mnemonic = ashCoreService.generateMnemonic(padBytes)
                Log.d(TAG, "Generated mnemonic: ${mnemonic.joinToString(" ")}")

                // Derive tokens for debugging
                try {
                    val tokens = ashCoreService.deriveAllTokens(padBytes)
                    Log.d(TAG, "Derived conversation ID: ${tokens.conversationId}")
                    Log.d(TAG, "Derived auth token: ${tokens.authToken.take(16)}...")
                } catch (e: Exception) {
                    Log.w(TAG, "Could not derive tokens for debug: ${e.message}")
                }

                // Generate QR codes using FFI fountain codes
                preGenerateQRCodes(padBytes)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to generate pad: ${e.message}", e)
                _phase.value = CeremonyPhase.Failed(CeremonyError.QR_GENERATION_FAILED)
            }
        }
    }

    private fun generatePadBytes(entropy: ByteArray, sizeBytes: Int): ByteArray {
        // Mix user entropy with secure random for additional security
        val secureRandom = SecureRandom()
        val systemEntropy = ByteArray(32)
        secureRandom.nextBytes(systemEntropy)

        // Combine entropies
        val combinedEntropy = entropy + systemEntropy

        // Generate pad bytes - use simple secure random with combined entropy as seed
        // The Rust Pad.fromEntropy expects exactly padSize bytes of entropy
        // So we generate padSize bytes using seeded SecureRandom
        val seededRandom = SecureRandom(combinedEntropy)
        val pad = ByteArray(sizeBytes)
        seededRandom.nextBytes(pad)
        return pad
    }

    private suspend fun preGenerateQRCodes(padBytes: ByteArray) {
        try {
            // Build ceremony metadata using FFI struct
            val metadata =
                CeremonyMetadata(
                    version = 1u,
                    ttlSeconds = _serverRetention.value.seconds.toULong(),
                    disappearingMessagesSeconds = (_disappearingMessages.value.seconds ?: 0).toUInt(),
                    notificationFlags = buildNotificationFlags(),
                    relayUrl = _relayUrl.value
                )

            // Use passphrase if enabled, otherwise null
            val passphraseToUse = if (_passphraseEnabled.value) _passphrase.value.ifEmpty { null } else null

            Log.d(
                TAG,
                "Creating fountain generator: blockSize=$FOUNTAIN_BLOCK_SIZE, passphraseEnabled=${_passphraseEnabled.value}"
            )

            // Create fountain generator using FFI
            val generator =
                withContext(Dispatchers.Default) {
                    ashCoreService.createFountainGenerator(
                        metadata = metadata,
                        padBytes = padBytes,
                        blockSize = FOUNTAIN_BLOCK_SIZE,
                        passphrase = passphraseToUse
                    )
                }
            fountainGenerator = generator

            val sourceCount = generator.sourceCount().toInt()
            _totalFrames.value = sourceCount

            Log.d(
                TAG,
                "Fountain generator created: sourceCount=$sourceCount, blockSize=${generator.blockSize()}, totalSize=${generator.totalSize()}"
            )

            val images = mutableListOf<Bitmap>()

            withContext(Dispatchers.Default) {
                for (index in 0 until sourceCount) {
                    _phase.value =
                        CeremonyPhase.GeneratingQRCodes(
                            progress = (index + 1).toFloat() / sourceCount,
                            total = sourceCount
                        )

                    // Generate frame using FFI
                    val frameBytes =
                        with(ashCoreService) {
                            generator.generateFrameBytes(index.toUInt())
                        }

                    Log.d(TAG, "Frame $index: ${frameBytes.size} bytes")

                    val bitmap = qrCodeService.generate(frameBytes, QR_CODE_SIZE)
                    if (bitmap != null) {
                        images.add(bitmap)
                    } else {
                        Log.e(TAG, "Failed to generate QR code for frame $index")
                        withContext(Dispatchers.Main) {
                            _phase.value = CeremonyPhase.Failed(CeremonyError.QR_GENERATION_FAILED)
                        }
                        return@withContext
                    }
                }
            }

            Log.d(TAG, "Successfully generated ${images.size} QR codes")
            preGeneratedQRImages = images
            _phase.value = CeremonyPhase.Transferring(currentFrame = 0, totalFrames = sourceCount)
            startDisplayCycling()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to generate QR codes: ${e.message}", e)
            _phase.value = CeremonyPhase.Failed(CeremonyError.QR_GENERATION_FAILED)
        }
    }

    private fun buildNotificationFlags(): UShort {
        // Notification flags bitfield:
        // Bit 0: NOTIFY_NEW_MESSAGE (0x0001)
        // Bit 1: NOTIFY_MESSAGE_EXPIRING (0x0002)
        // Bit 2: NOTIFY_MESSAGE_EXPIRED (0x0004)
        // Bit 8: NOTIFY_DELIVERY_FAILED (0x0100)
        // Bits 12-15: Color encoding
        val colorIndex = _selectedColor.value.ordinal
        val flags = (colorIndex shl 12) or 0x0103 // Default: new message + expiring + delivery failed
        return flags.toUShort()
    }

    // MARK: - QR Display Cycling

    private fun startDisplayCycling() {
        displayJob?.cancel()
        _currentFrameIndex.value = 0
        _isPaused.value = false
        _currentQRBitmap.value = preGeneratedQRImages.firstOrNull()

        displayJob =
            viewModelScope.launch {
                while (isActive && preGeneratedQRImages.isNotEmpty()) {
                    val delayMs = 1000L / _fps.value
                    delay(delayMs)

                    if (!_isPaused.value) {
                        val nextIndex = (_currentFrameIndex.value + 1) % preGeneratedQRImages.size
                        _currentFrameIndex.value = nextIndex
                        _currentQRBitmap.value = preGeneratedQRImages[nextIndex]

                        if (_phase.value is CeremonyPhase.Transferring) {
                            _phase.value =
                                CeremonyPhase.Transferring(
                                    currentFrame = nextIndex % _totalFrames.value,
                                    totalFrames = _totalFrames.value
                                )
                        }
                    }
                }
            }
    }

    fun stopDisplayCycling() {
        displayJob?.cancel()
        displayJob = null
    }

    // MARK: - Playback Controls

    fun togglePause() {
        _isPaused.value = !_isPaused.value
    }

    fun setFps(newFps: Int) {
        _fps.value = newFps.coerceIn(1, 10)
    }

    fun previousFrame() {
        if (preGeneratedQRImages.isEmpty()) return
        val prevIndex =
            if (_currentFrameIndex.value > 0) {
                _currentFrameIndex.value - 1
            } else {
                preGeneratedQRImages.size - 1
            }
        _currentFrameIndex.value = prevIndex
        _currentQRBitmap.value = preGeneratedQRImages[prevIndex]
        updateTransferringPhase(prevIndex)
    }

    fun nextFrame() {
        if (preGeneratedQRImages.isEmpty()) return
        val nextIndex = (_currentFrameIndex.value + 1) % preGeneratedQRImages.size
        _currentFrameIndex.value = nextIndex
        _currentQRBitmap.value = preGeneratedQRImages[nextIndex]
        updateTransferringPhase(nextIndex)
    }

    fun firstFrame() {
        if (preGeneratedQRImages.isEmpty()) return
        _currentFrameIndex.value = 0
        _currentQRBitmap.value = preGeneratedQRImages.first()
        updateTransferringPhase(0)
    }

    fun lastFrame() {
        if (preGeneratedQRImages.isEmpty()) return
        val lastIndex = preGeneratedQRImages.size - 1
        _currentFrameIndex.value = lastIndex
        _currentQRBitmap.value = preGeneratedQRImages[lastIndex]
        updateTransferringPhase(lastIndex)
    }

    fun resetFrames() {
        _currentFrameIndex.value = 0
        _currentQRBitmap.value = preGeneratedQRImages.firstOrNull()
        _isPaused.value = false
        updateTransferringPhase(0)
    }

    private fun updateTransferringPhase(frameIndex: Int) {
        if (_phase.value is CeremonyPhase.Transferring) {
            _phase.value =
                CeremonyPhase.Transferring(
                    currentFrame = frameIndex % _totalFrames.value,
                    totalFrames = _totalFrames.value
                )
        }
    }

    // MARK: - Verification

    fun finishSending() {
        stopDisplayCycling()
        _phase.value = CeremonyPhase.Verifying(mnemonic = mnemonic)
    }

    fun confirmVerification(): Conversation? {
        val padBytes = generatedPadBytes ?: return null

        try {
            // Derive all tokens using FFI
            val tokens = ashCoreService.deriveAllTokens(padBytes)

            val conversation =
                Conversation(
                    id = tokens.conversationId,
                    name = _conversationName.value.ifBlank { null },
                    relayUrl = _relayUrl.value,
                    authToken = tokens.authToken,
                    burnToken = tokens.burnToken,
                    role = ConversationRole.INITIATOR,
                    color = _selectedColor.value,
                    createdAt = System.currentTimeMillis(),
                    padTotalSize = padBytes.size.toLong(),
                    mnemonic = mnemonic,
                    messageRetention = _serverRetention.value,
                    disappearingMessages = _disappearingMessages.value
                )

            viewModelScope.launch {
                conversationStorage.saveConversation(conversation)
                padManager.storePad(padBytes, conversation.id)

                // Register conversation with relay (fire-and-forget)
                registerConversationWithRelay(conversation)
            }

            _phase.value = CeremonyPhase.Completed(conversation)
            return conversation
        } catch (e: Exception) {
            Log.e(TAG, "Failed to confirm verification: ${e.message}", e)
            _phase.value = CeremonyPhase.Failed(CeremonyError.QR_GENERATION_FAILED)
            return null
        }
    }

    private suspend fun registerConversationWithRelay(conversation: Conversation) {
        try {
            val authTokenHash = relayService.hashToken(conversation.authToken)
            val burnTokenHash = relayService.hashToken(conversation.burnToken)
            val result =
                relayService.registerConversation(
                    conversationId = conversation.id,
                    authTokenHash = authTokenHash,
                    burnTokenHash = burnTokenHash,
                    relayUrl = conversation.relayUrl
                )
            if (result.isSuccess) {
                Log.d(TAG, "Conversation registered with relay")
            } else {
                Log.w(TAG, "Failed to register conversation with relay: ${result.exceptionOrNull()?.message}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register conversation with relay: ${e.message}")
        }
    }

    fun rejectVerification() {
        _phase.value = CeremonyPhase.Failed(CeremonyError.CHECKSUM_MISMATCH)
    }

    // MARK: - Reset & Cancel

    fun reset() {
        stopDisplayCycling()
        fountainGenerator?.close()
        fountainGenerator = null

        _phase.value = CeremonyPhase.SelectingPadSize
        _selectedPadSize.value = PadSize.MEDIUM
        _selectedColor.value = ConversationColor.INDIGO
        _conversationName.value = ""
        _serverRetention.value = MessageRetention.ONE_DAY
        _disappearingMessages.value = DisappearingMessages.OFF
        _consent.value = ConsentState()
        _entropyProgress.value = 0f
        _currentQRBitmap.value = null
        _currentFrameIndex.value = 0
        _totalFrames.value = 0
        _connectionTestResult.value = null
        _passphraseEnabled.value = false
        _passphrase.value = ""
        _isPaused.value = false
        _fps.value = 7 // Reset to default ~7 FPS
        collectedEntropy.clear()
        generatedPadBytes = null
        preGeneratedQRImages = emptyList()
        mnemonic = emptyList()
        isGeneratingPad = false

        viewModelScope.launch {
            _relayUrl.value = settingsService.getRelayUrl()
        }
    }

    fun cancel() {
        stopDisplayCycling()
        fountainGenerator?.close()
        fountainGenerator = null
        _phase.value = CeremonyPhase.Failed(CeremonyError.CANCELLED)
    }

    override fun onCleared() {
        super.onCleared()
        stopDisplayCycling()
        fountainGenerator?.close()
        fountainGenerator = null
    }
}
