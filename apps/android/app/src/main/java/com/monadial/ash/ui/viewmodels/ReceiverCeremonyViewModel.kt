package com.monadial.ash.ui.viewmodels

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.monadial.ash.domain.services.QRCodeService
import com.monadial.ash.domain.entities.CeremonyError
import com.monadial.ash.domain.entities.CeremonyPhase
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.entities.ConversationColor
import com.monadial.ash.domain.entities.ConversationRole
import com.monadial.ash.domain.entities.DisappearingMessages
import com.monadial.ash.domain.entities.MessageRetention
import com.monadial.ash.domain.repositories.ConversationRepository
import com.monadial.ash.domain.repositories.PadRepository
import com.monadial.ash.domain.services.CryptoService
import com.monadial.ash.domain.usecases.conversation.RegisterConversationUseCase
import com.monadial.ash.ui.state.ReceiverCeremonyUiState
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import uniffi.ash.FountainCeremonyResult
import uniffi.ash.FountainFrameReceiver

/**
 * ViewModel for the receiver (scanner) ceremony flow.
 *
 * Follows Clean Architecture and MVVM patterns:
 * - Single UiState for all screen state
 * - Repositories for data access
 * - Domain Services for crypto operations
 * - Use Cases for business logic
 */
@HiltViewModel
class ReceiverCeremonyViewModel @Inject constructor(
    private val qrCodeService: QRCodeService,
    private val conversationRepository: ConversationRepository,
    private val cryptoService: CryptoService,
    private val padRepository: PadRepository,
    private val registerConversationUseCase: RegisterConversationUseCase
) : ViewModel() {

    companion object {
        private const val TAG = "ReceiverCeremonyVM"
    }

    // Single consolidated UI state
    private val _uiState = MutableStateFlow(ReceiverCeremonyUiState())
    val uiState: StateFlow<ReceiverCeremonyUiState> = _uiState.asStateFlow()

    // Internal state (not exposed to UI)
    private var fountainReceiver: FountainFrameReceiver? = null
    private var ceremonyResult: FountainCeremonyResult? = null
    private var reconstructedPadBytes: ByteArray? = null
    private var mnemonic: List<String> = emptyList()

    // MARK: - Configuration

    fun setConversationName(name: String) {
        _uiState.update { it.copy(conversationName = name) }
    }

    fun setPassphraseEnabled(enabled: Boolean) {
        _uiState.update {
            it.copy(
                passphraseEnabled = enabled,
                passphrase = if (!enabled) "" else it.passphrase
            )
        }
    }

    fun setPassphrase(value: String) {
        _uiState.update { it.copy(passphrase = value) }
    }

    fun setSelectedColor(color: ConversationColor) {
        _uiState.update { it.copy(selectedColor = color) }
    }

    // MARK: - Scanning

    fun startScanning() {
        val state = _uiState.value
        val passphraseToUse = if (state.passphraseEnabled) {
            state.passphrase.ifEmpty { null }
        } else null

        // Create a new fountain receiver
        fountainReceiver?.close()
        fountainReceiver = cryptoService.createFountainReceiver(passphrase = passphraseToUse)

        // Reset internal state
        ceremonyResult = null
        reconstructedPadBytes = null
        mnemonic = emptyList()

        // Update UI state
        _uiState.update {
            it.copy(
                phase = CeremonyPhase.Scanning,
                receivedBlocks = 0,
                totalBlocks = 0,
                progress = 0f
            )
        }

        Log.d(TAG, "Started scanning with new fountain receiver, passphraseEnabled=${state.passphraseEnabled}")
    }

    fun processScannedFrame(base64String: String) {
        val receiver = fountainReceiver ?: return
        val frameBytes = qrCodeService.decodeBase64(base64String) ?: return

        if (frameBytes.isEmpty()) return

        try {
            val isComplete = cryptoService.addFrameBytes(receiver, frameBytes)

            val uniqueBlocks = receiver.uniqueBlocksReceived().toInt()
            val sourceCount = receiver.sourceCount().toInt()
            val progress = receiver.progress().toFloat()

            _uiState.update {
                it.copy(
                    receivedBlocks = uniqueBlocks,
                    totalBlocks = sourceCount,
                    progress = progress,
                    phase = CeremonyPhase.Transferring(
                        currentFrame = uniqueBlocks,
                        totalFrames = sourceCount
                    )
                )
            }

            Log.d(TAG, "Frame processed: unique=$uniqueBlocks, sourceCount=$sourceCount, progress=${(progress * 100).toInt()}%")

            if (isComplete || receiver.isComplete()) {
                reconstructAndVerify()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to process frame: ${e.message}", e)
        }
    }

    // MARK: - Reconstruction

    private fun reconstructAndVerify() {
        val receiver = fountainReceiver ?: run {
            _uiState.update { it.copy(phase = CeremonyPhase.Failed(CeremonyError.PAD_RECONSTRUCTION_FAILED)) }
            return
        }

        try {
            val result = receiver.getResult()
            if (result == null) {
                Log.e(TAG, "Receiver reported complete but getResult() returned null")
                _uiState.update { it.copy(phase = CeremonyPhase.Failed(CeremonyError.PAD_RECONSTRUCTION_FAILED)) }
                return
            }

            ceremonyResult = result
            val padUBytes = result.pad

            Log.d(TAG, "Reconstructed pad: ${padUBytes.size} bytes, blocks used: ${result.blocksUsed}")
            Log.d(TAG, "Metadata: ttl=${result.metadata.ttlSeconds}, relayUrl=${result.metadata.relayUrl}")

            // Extract color from notification flags
            val colorIndex = ((result.metadata.notificationFlags.toInt()) shr 12) and 0x0F
            val decodedColor = ConversationColor.entries.getOrElse(colorIndex) { ConversationColor.INDIGO }
            _uiState.update { it.copy(selectedColor = decodedColor) }
            Log.d(TAG, "Decoded conversation color: $decodedColor (index=$colorIndex)")

            logPadDebugInfo(padUBytes)

            // Generate mnemonic using FFI (takes List<UByte>)
            mnemonic = uniffi.ash.generateMnemonic(padUBytes)
            Log.d(TAG, "Generated mnemonic: ${mnemonic.joinToString(" ")}")

            // Derive tokens for debugging
            val tokens = uniffi.ash.deriveAllTokens(padUBytes)
            Log.d(TAG, "Derived conversation ID: ${tokens.conversationId}")

            reconstructedPadBytes = padUBytes.map { it.toByte() }.toByteArray()

            _uiState.update { it.copy(phase = CeremonyPhase.Verifying(mnemonic = mnemonic)) }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reconstruct ceremony: ${e.message}", e)
            _uiState.update { it.copy(phase = CeremonyPhase.Failed(CeremonyError.PAD_RECONSTRUCTION_FAILED)) }
        }
    }

    private fun logPadDebugInfo(padUBytes: List<UByte>) {
        val firstBytes = padUBytes.take(16).joinToString("") { String.format("%02X", it.toInt()) }
        val lastBytes = padUBytes.takeLast(16).joinToString("") { String.format("%02X", it.toInt()) }
        Log.d(TAG, "Pad first 16 bytes: $firstBytes")
        Log.d(TAG, "Pad last 16 bytes: $lastBytes")
    }

    // MARK: - Verification

    fun confirmVerification(): Conversation? {
        val result = ceremonyResult ?: return null
        val padUBytes = result.pad
        val metadata = result.metadata
        val state = _uiState.value

        try {
            // Derive tokens using FFI directly (takes List<UByte>)
            val tokens = uniffi.ash.deriveAllTokens(padUBytes)

            val messageRetention = MessageRetention.fromSeconds(metadata.ttlSeconds.toLong())
            val disappearingMessages = DisappearingMessages.fromSeconds(metadata.disappearingMessagesSeconds.toInt())

            val conversation = Conversation(
                id = tokens.conversationId,
                name = state.conversationName.ifBlank { null },
                relayUrl = metadata.relayUrl,
                authToken = tokens.authToken,
                burnToken = tokens.burnToken,
                role = ConversationRole.RESPONDER,
                color = state.selectedColor,
                createdAt = System.currentTimeMillis(),
                padTotalSize = padUBytes.size.toLong(),
                mnemonic = mnemonic,
                messageRetention = messageRetention,
                disappearingMessages = disappearingMessages
            )

            val padBytes = padUBytes.map { it.toByte() }.toByteArray()
            viewModelScope.launch {
                conversationRepository.saveConversation(conversation)
                padRepository.storePad(conversation.id, padBytes)
                registerConversationUseCase(conversation)
            }

            _uiState.update { it.copy(phase = CeremonyPhase.Completed(conversation)) }
            return conversation
        } catch (e: Exception) {
            Log.e(TAG, "Failed to confirm verification: ${e.message}", e)
            _uiState.update { it.copy(phase = CeremonyPhase.Failed(CeremonyError.PAD_RECONSTRUCTION_FAILED)) }
            return null
        }
    }

    fun rejectVerification() {
        _uiState.update { it.copy(phase = CeremonyPhase.Failed(CeremonyError.CHECKSUM_MISMATCH)) }
    }

    // MARK: - Reset & Cancel

    fun reset() {
        cleanupResources()

        _uiState.value = ReceiverCeremonyUiState()
        ceremonyResult = null
        reconstructedPadBytes = null
        mnemonic = emptyList()
    }

    fun cancel() {
        cleanupResources()
        _uiState.update { it.copy(phase = CeremonyPhase.Failed(CeremonyError.CANCELLED)) }
    }

    private fun cleanupResources() {
        fountainReceiver?.close()
        fountainReceiver = null
    }

    override fun onCleared() {
        super.onCleared()
        cleanupResources()
    }
}
