package com.monadial.ash.ui.viewmodels

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
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.entities.ConversationColor
import com.monadial.ash.domain.entities.ConversationRole
import com.monadial.ash.domain.entities.DisappearingMessages
import com.monadial.ash.domain.entities.MessageRetention
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.ash.CeremonyMetadata
import uniffi.ash.FountainCeremonyResult
import uniffi.ash.FountainFrameReceiver
import javax.inject.Inject

@HiltViewModel
class ReceiverCeremonyViewModel @Inject constructor(
    private val settingsService: SettingsService,
    private val qrCodeService: QRCodeService,
    private val conversationStorage: ConversationStorageService,
    private val ashCoreService: AshCoreService,
    private val relayService: RelayService,
    private val padManager: PadManager
) : ViewModel() {

    companion object {
        private const val TAG = "ReceiverCeremonyVM"
    }

    // State
    private val _phase = MutableStateFlow<CeremonyPhase>(CeremonyPhase.ConfiguringReceiver)
    val phase: StateFlow<CeremonyPhase> = _phase.asStateFlow()

    private val _conversationName = MutableStateFlow("")
    val conversationName: StateFlow<String> = _conversationName.asStateFlow()

    private val _receivedBlocks = MutableStateFlow(0)
    val receivedBlocks: StateFlow<Int> = _receivedBlocks.asStateFlow()

    private val _totalBlocks = MutableStateFlow(0)
    val totalBlocks: StateFlow<Int> = _totalBlocks.asStateFlow()

    private val _progress = MutableStateFlow(0f)
    val progress: StateFlow<Float> = _progress.asStateFlow()

    // Private state - now using FFI receiver
    private var fountainReceiver: FountainFrameReceiver? = null
    private var ceremonyResult: FountainCeremonyResult? = null
    private var reconstructedPadBytes: ByteArray? = null
    private var mnemonic: List<String> = emptyList()

    // MARK: - Scanning Setup

    fun startScanning() {
        // Create a new fountain receiver using FFI
        fountainReceiver?.close()
        fountainReceiver = ashCoreService.createFountainReceiver(passphrase = null)

        _phase.value = CeremonyPhase.Scanning
        _receivedBlocks.value = 0
        _totalBlocks.value = 0
        _progress.value = 0f
        ceremonyResult = null
        reconstructedPadBytes = null
        mnemonic = emptyList()

        Log.d(TAG, "Started scanning with new fountain receiver")
    }

    fun setConversationName(name: String) {
        _conversationName.value = name
    }

    // MARK: - Frame Processing

    fun processScannedFrame(base64String: String) {
        val receiver = fountainReceiver ?: return
        val frameBytes = qrCodeService.decodeBase64(base64String) ?: return

        if (frameBytes.isEmpty()) return

        try {
            // Add frame to receiver using FFI
            val isComplete = with(ashCoreService) {
                receiver.addFrameBytes(frameBytes)
            }

            // Update progress
            val blocksReceived = receiver.blocksReceived().toInt()
            val sourceCount = receiver.sourceCount().toInt()
            val progress = receiver.progress().toFloat()

            _receivedBlocks.value = blocksReceived
            _totalBlocks.value = sourceCount
            _progress.value = progress

            Log.d(TAG, "Frame processed: received=$blocksReceived, total=$sourceCount, progress=${(progress * 100).toInt()}%")

            // Update phase
            _phase.value = CeremonyPhase.Transferring(
                currentFrame = blocksReceived,
                totalFrames = sourceCount
            )

            // Check if complete
            if (isComplete || receiver.isComplete()) {
                reconstructAndVerify()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to process frame: ${e.message}", e)
            // Ignore invalid frames, continue scanning
        }
    }

    // MARK: - Reconstruction

    private fun reconstructAndVerify() {
        val receiver = fountainReceiver ?: run {
            _phase.value = CeremonyPhase.Failed(CeremonyError.PAD_RECONSTRUCTION_FAILED)
            return
        }

        try {
            // Get the decoded result from FFI receiver
            val result = receiver.getResult()
            if (result == null) {
                Log.e(TAG, "Receiver reported complete but getResult() returned null")
                _phase.value = CeremonyPhase.Failed(CeremonyError.PAD_RECONSTRUCTION_FAILED)
                return
            }

            ceremonyResult = result

            // Use pad directly from FFI result (List<UByte>) for mnemonic/tokens
            // to avoid any byte conversion issues
            val padUBytes = result.pad

            Log.d(TAG, "Reconstructed pad: ${padUBytes.size} bytes, blocks used: ${result.blocksUsed}")
            Log.d(TAG, "Metadata: ttl=${result.metadata.ttlSeconds}, relayUrl=${result.metadata.relayUrl}")

            // Log first and last 16 bytes of pad for debugging (as hex)
            val firstBytes = padUBytes.take(16).map { String.format("%02X", it.toInt()) }.joinToString("")
            val lastBytes = padUBytes.takeLast(16).map { String.format("%02X", it.toInt()) }.joinToString("")
            Log.d(TAG, "Pad first 16 bytes: $firstBytes")
            Log.d(TAG, "Pad last 16 bytes: $lastBytes")

            // Generate mnemonic from pad using FFI directly with UByte list
            mnemonic = uniffi.ash.generateMnemonic(padUBytes)
            Log.d(TAG, "Generated mnemonic: ${mnemonic.joinToString(" ")}")

            // Also derive tokens for debugging - use FFI directly
            val tokens = uniffi.ash.deriveAllTokens(padUBytes)
            Log.d(TAG, "Derived conversation ID: ${tokens.conversationId}")
            Log.d(TAG, "Derived auth token: ${tokens.authToken.take(16)}...")

            // Store as ByteArray for later use
            reconstructedPadBytes = padUBytes.map { it.toByte() }.toByteArray()

            _phase.value = CeremonyPhase.Verifying(mnemonic = mnemonic)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reconstruct ceremony: ${e.message}", e)
            _phase.value = CeremonyPhase.Failed(CeremonyError.PAD_RECONSTRUCTION_FAILED)
        }
    }

    // MARK: - Verification

    fun confirmVerification(): Conversation? {
        val result = ceremonyResult ?: return null
        val padUBytes = result.pad
        val metadata = result.metadata

        try {
            // Derive all tokens using FFI directly with UByte list
            val tokens = uniffi.ash.deriveAllTokens(padUBytes)

            // Extract color from notification flags
            val colorIndex = ((metadata.notificationFlags.toInt()) shr 12) and 0x0F
            val color = ConversationColor.entries.getOrElse(colorIndex) { ConversationColor.INDIGO }

            // Map FFI metadata to domain entities
            val messageRetention = MessageRetention.fromSeconds(metadata.ttlSeconds.toLong())
            val disappearingMessages = DisappearingMessages.fromSeconds(metadata.disappearingMessagesSeconds.toInt())

            val conversation = Conversation(
                id = tokens.conversationId,
                name = _conversationName.value.ifBlank { "New Conversation" },
                relayUrl = metadata.relayUrl,
                authToken = tokens.authToken,
                burnToken = tokens.burnToken,
                role = ConversationRole.RESPONDER,
                color = color,
                createdAt = System.currentTimeMillis(),
                padTotalSize = padUBytes.size.toLong(),
                mnemonic = mnemonic,
                messageRetention = messageRetention,
                disappearingMessages = disappearingMessages
            )

            // Convert to ByteArray for storage
            val padBytes = padUBytes.map { it.toByte() }.toByteArray()
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
            _phase.value = CeremonyPhase.Failed(CeremonyError.PAD_RECONSTRUCTION_FAILED)
            return null
        }
    }

    private suspend fun registerConversationWithRelay(conversation: Conversation) {
        try {
            val authTokenHash = relayService.hashToken(conversation.authToken)
            val burnTokenHash = relayService.hashToken(conversation.burnToken)
            val result = relayService.registerConversation(
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
        fountainReceiver?.close()
        fountainReceiver = null

        _phase.value = CeremonyPhase.ConfiguringReceiver
        _conversationName.value = ""
        _receivedBlocks.value = 0
        _totalBlocks.value = 0
        _progress.value = 0f
        ceremonyResult = null
        reconstructedPadBytes = null
        mnemonic = emptyList()
    }

    fun cancel() {
        fountainReceiver?.close()
        fountainReceiver = null
        _phase.value = CeremonyPhase.Failed(CeremonyError.CANCELLED)
    }

    override fun onCleared() {
        super.onCleared()
        fountainReceiver?.close()
        fountainReceiver = null
    }
}
