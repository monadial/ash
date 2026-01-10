package com.monadial.ash.ui.viewmodels

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.monadial.ash.core.services.AshCoreService
import com.monadial.ash.core.services.ConversationStorageService
import com.monadial.ash.core.services.LocationService
import com.monadial.ash.core.services.PadManager
import com.monadial.ash.core.services.ReceivedMessage
import com.monadial.ash.core.services.RelayService
import com.monadial.ash.core.services.SSEEvent
import com.monadial.ash.core.services.SSEService
import uniffi.ash.Role
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.entities.ConversationRole
import com.monadial.ash.domain.entities.DeliveryStatus
import com.monadial.ash.domain.entities.Message
import com.monadial.ash.domain.entities.MessageContent
import com.monadial.ash.domain.entities.MessageDirection
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class MessagingViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val conversationStorage: ConversationStorageService,
    private val relayService: RelayService,
    private val sseService: SSEService,
    private val locationService: LocationService,
    private val ashCoreService: AshCoreService,
    private val padManager: PadManager
) : ViewModel() {

    private val conversationId: String = savedStateHandle["conversationId"]!!

    private val _conversation = MutableStateFlow<Conversation?>(null)
    val conversation: StateFlow<Conversation?> = _conversation.asStateFlow()

    private val _messages = MutableStateFlow<List<Message>>(emptyList())
    val messages: StateFlow<List<Message>> = _messages.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isSending = MutableStateFlow(false)
    val isSending: StateFlow<Boolean> = _isSending.asStateFlow()

    private val _isGettingLocation = MutableStateFlow(false)
    val isGettingLocation: StateFlow<Boolean> = _isGettingLocation.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _inputText = MutableStateFlow("")
    val inputText: StateFlow<String> = _inputText.asStateFlow()

    private val _peerBurned = MutableStateFlow(false)
    val peerBurned: StateFlow<Boolean> = _peerBurned.asStateFlow()

    private var sseJob: Job? = null
    private var pollingJob: Job? = null
    private var hasAttemptedRegistration: Boolean = false

    init {
        loadConversation()
    }

    private fun loadConversation() {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val conv = conversationStorage.getConversation(conversationId)
                _conversation.value = conv

                if (conv != null) {
                    // Check if peer has burned
                    if (conv.peerBurnedAt != null) {
                        _peerBurned.value = true
                    } else {
                        // Register conversation with relay before SSE (fire-and-forget)
                        registerConversationWithRelay(conv)
                        // Try SSE first, fall back to polling
                        startSSE(conv)
                        startPollingMessages()
                        checkBurnStatus(conv)
                    }
                }
            } catch (e: Exception) {
                _error.value = "Failed to load conversation: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    private suspend fun registerConversationWithRelay(conv: Conversation): Boolean {
        return try {
            val authTokenHash = relayService.hashToken(conv.authToken)
            val burnTokenHash = relayService.hashToken(conv.burnToken)
            val result = relayService.registerConversation(
                conversationId = conv.id,
                authTokenHash = authTokenHash,
                burnTokenHash = burnTokenHash,
                relayUrl = conv.relayUrl
            )
            result.isSuccess
        } catch (e: Exception) {
            false
        }
    }

    private fun startSSE(conv: Conversation) {
        sseJob?.cancel()
        sseJob = viewModelScope.launch {
            sseService.connect(
                relayUrl = conv.relayUrl,
                conversationId = conversationId,
                authToken = conv.authToken
            )

            sseService.events.collect { event ->
                when (event) {
                    is SSEEvent.MessageReceived -> {
                        handleReceivedMessage(
                            ReceivedMessage(
                                id = event.id,
                                ciphertext = event.ciphertext,
                                sequence = event.sequence,
                                receivedAt = event.receivedAt
                            )
                        )
                    }
                    is SSEEvent.DeliveryConfirmed -> {
                        event.blobIds.forEach { blobId ->
                            handleDeliveryConfirmation(blobId)
                        }
                    }
                    is SSEEvent.BurnSignal -> {
                        handlePeerBurn()
                    }
                    is SSEEvent.NotFound -> {
                        // Conversation not found on relay - try to register and reconnect
                        if (!hasAttemptedRegistration) {
                            hasAttemptedRegistration = true
                            if (registerConversationWithRelay(conv)) {
                                // Retry SSE connection after successful registration
                                startSSE(conv)
                            }
                        }
                    }
                    else -> { /* Ignore ping, connected, disconnected, error */ }
                }
            }
        }
    }

    private fun startPollingMessages() {
        pollingJob?.cancel()
        pollingJob = viewModelScope.launch {
            val conv = _conversation.value ?: return@launch

            relayService.pollMessages(
                relayUrl = conv.relayUrl,
                conversationId = conversationId,
                authToken = conv.authToken,
                cursor = conv.relayCursor
            ).collect { result ->
                if (result.success) {
                    result.messages.forEach { handleReceivedMessage(it) }
                }
            }
        }
    }

    private suspend fun handleReceivedMessage(received: ReceivedMessage) {
        val conv = _conversation.value ?: return

        // Check for duplicates using blob ID
        if (_messages.value.any { it.blobId == received.id }) {
            return
        }

        // sequence is the sender's consumption offset, not absolute pad position
        val senderOffset = received.sequence ?: return

        try {
            // Calculate absolute pad position based on peer's role
            // Initiator encrypts from front: absolute = senderOffset
            // Responder encrypts from back: absolute = padSize - senderOffset - length
            val absoluteOffset: Long
            val peerRole: Role

            if (conv.role == ConversationRole.INITIATOR) {
                // I'm initiator, peer is responder (encrypts from back)
                peerRole = Role.RESPONDER
                absoluteOffset = conv.padTotalSize - senderOffset - received.ciphertext.size
            } else {
                // I'm responder, peer is initiator (encrypts from front)
                peerRole = Role.INITIATOR
                absoluteOffset = senderOffset
            }

            // Get key bytes from pad at the absolute position
            val keyBytes = padManager.getBytesForDecryption(
                offset = absoluteOffset,
                length = received.ciphertext.size,
                conversationId = conversationId
            )

            // Decrypt using FFI
            val plaintext = ashCoreService.decrypt(keyBytes, received.ciphertext)

            val content = MessageContent.fromBytes(plaintext)
            val disappearingSeconds = conv.disappearingMessages.seconds?.toLong()

            val message = Message.incoming(
                conversationId = conversationId,
                content = content,
                sequence = senderOffset,
                disappearingSeconds = disappearingSeconds,
                blobId = received.id
            )

            _messages.value = _messages.value + message

            // Update peer consumption tracking using PadManager
            val consumedAmount = senderOffset + received.ciphertext.size
            padManager.updatePeerConsumption(peerRole, consumedAmount, conversationId)

            // Send ACK
            sendAck(received.id)
        } catch (e: Exception) {
            // Decryption failed
        }
    }

    private fun handleDeliveryConfirmation(messageId: String) {
        _messages.value = _messages.value.map { msg ->
            if (msg.blobId == messageId) {
                msg.withDeliveryStatus(DeliveryStatus.DELIVERED)
            } else {
                msg
            }
        }
    }

    private fun handlePeerBurn() {
        _peerBurned.value = true
        viewModelScope.launch {
            val conv = _conversation.value ?: return@launch
            val updated = conv.copy(peerBurnedAt = System.currentTimeMillis())
            conversationStorage.saveConversation(updated)
            _conversation.value = updated
        }
    }

    private suspend fun checkBurnStatus(conv: Conversation) {
        val result = relayService.checkBurnStatus(
            conversationId = conv.id,
            authToken = conv.authToken,
            relayUrl = conv.relayUrl
        )
        result.onSuccess { status ->
            if (status.burned) {
                handlePeerBurn()
            }
        }
    }

    private suspend fun sendAck(messageId: String) {
        val conv = _conversation.value ?: return
        relayService.acknowledgeMessages(
            conversationId = conversationId,
            authToken = conv.authToken,
            blobIds = listOf(messageId),
            relayUrl = conv.relayUrl
        )
    }

    fun setInputText(text: String) {
        _inputText.value = text
    }

    fun sendMessage() {
        val text = _inputText.value.trim()
        if (text.isEmpty()) return

        val content = MessageContent.Text(text)
        sendMessageContent(content)
        _inputText.value = ""
    }

    fun sendLocation() {
        viewModelScope.launch {
            _isGettingLocation.value = true
            try {
                val result = locationService.getCurrentLocation()
                result.onSuccess { locationResult ->
                    val content = MessageContent.Location(locationResult.latitude, locationResult.longitude)
                    sendMessageContent(content)
                }.onFailure { e ->
                    _error.value = when (e) {
                        is com.monadial.ash.core.services.LocationError.PermissionDenied ->
                            "Location permission required"
                        is com.monadial.ash.core.services.LocationError.LocationUnavailable ->
                            "Location unavailable"
                        else -> "Failed to get location: ${e.message}"
                    }
                }
            } finally {
                _isGettingLocation.value = false
            }
        }
    }

    private fun sendMessageContent(content: MessageContent) {
        val conv = _conversation.value ?: return

        viewModelScope.launch {
            _isSending.value = true
            try {
                val plaintext = MessageContent.toBytes(content)
                val myRole = if (conv.role == ConversationRole.INITIATOR) Role.INITIATOR else Role.RESPONDER

                // Get the next send offset from PadManager
                val currentOffset = padManager.nextSendOffset(myRole, conversationId)

                // Check if we can send
                if (!padManager.canSend(plaintext.size, myRole, conversationId)) {
                    _error.value = "Pad exhausted - cannot send message"
                    return@launch
                }

                // Consume pad bytes for encryption (this updates state in PadManager)
                val keyBytes = padManager.consumeForSending(plaintext.size, myRole, conversationId)

                // Encrypt using FFI
                val ciphertext = ashCoreService.encrypt(keyBytes, plaintext)

                // Create message
                val message = Message(
                    conversationId = conversationId,
                    content = content,
                    direction = MessageDirection.SENT,
                    status = DeliveryStatus.SENDING,
                    sequence = currentOffset,
                    serverExpiresAt = System.currentTimeMillis() + (conv.messageRetention.seconds * 1000L)
                )

                // Add to local list immediately
                _messages.value = _messages.value + message

                // Send to relay (matching iOS: POST /v1/messages)
                val sendResult = relayService.submitMessage(
                    conversationId = conversationId,
                    authToken = conv.authToken,
                    ciphertext = ciphertext,
                    sequence = currentOffset,
                    ttlSeconds = conv.messageRetention.seconds,
                    relayUrl = conv.relayUrl
                )

                if (sendResult.success && sendResult.blobId != null) {
                    // Update message with blob ID and status
                    _messages.value = _messages.value.map {
                        if (it.id == message.id) {
                            it.withBlobId(sendResult.blobId).withDeliveryStatus(DeliveryStatus.SENT)
                        } else it
                    }
                } else {
                    // Mark as failed
                    _messages.value = _messages.value.map {
                        if (it.id == message.id) {
                            it.withDeliveryStatus(DeliveryStatus.FAILED(sendResult.error))
                        } else it
                    }
                    _error.value = sendResult.error ?: "Failed to send message"
                }
            } catch (e: Exception) {
                _error.value = "Failed to send message: ${e.message}"
            } finally {
                _isSending.value = false
            }
        }
    }

    fun clearError() {
        _error.value = null
    }

    fun retryMessage(messageId: String) {
        val message = _messages.value.find { it.id == messageId } ?: return
        if (!message.status.isFailed) return

        // Remove failed message and re-send
        _messages.value = _messages.value.filter { it.id != messageId }
        sendMessageContent(message.content)
    }

    val padUsagePercentage: Float
        get() {
            val conv = _conversation.value ?: return 0f
            val total = conv.padTotalSize
            if (total == 0L) return 0f
            return ((conv.padConsumedFront + conv.padConsumedBack).toFloat() / total) * 100
        }

    val remainingBytes: Long
        get() {
            val conv = _conversation.value ?: return 0L
            return conv.padTotalSize - conv.padConsumedFront - conv.padConsumedBack
        }

    override fun onCleared() {
        super.onCleared()
        sseJob?.cancel()
        pollingJob?.cancel()
        sseService.disconnect()
    }
}
