package com.monadial.ash.ui.viewmodels

import android.util.Log
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
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.entities.ConversationRole
import com.monadial.ash.domain.entities.DeliveryStatus
import com.monadial.ash.domain.entities.Message
import com.monadial.ash.domain.entities.MessageContent
import com.monadial.ash.domain.entities.MessageDirection
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.ash.Role

private const val TAG = "MessagingViewModel"

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

    // Track sent messages to filter out own message echoes from SSE (matching iOS)
    private val sentSequences = mutableSetOf<Long>()
    private val sentBlobIds = mutableSetOf<String>()
    private val processedBlobIds = mutableSetOf<String>()

    // Short ID for logging (first 8 chars)
    private val logId: String get() = conversationId.take(8)

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
            val result =
                relayService.registerConversation(
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
        sseJob =
            viewModelScope.launch {
                sseService.connect(
                    relayUrl = conv.relayUrl,
                    conversationId = conversationId,
                    authToken = conv.authToken
                )

                sseService.events.collect { event ->
                    when (event) {
                        is SSEEvent.Connected -> {
                            Log.i(TAG, "[$logId] SSE connected")
                        }
                        is SSEEvent.MessageReceived -> {
                            Log.d(TAG, "[$logId] SSE raw: ${event.ciphertext.size} bytes, seq=${event.sequence}, blobId=${event.id.take(8)}")
                            Log.d(
                                TAG,
                                "[$logId] sentSequences=$sentSequences, sentBlobIds=${sentBlobIds.map {
                                    it.take(8)
                                }}"
                            )

                            // Filter out own messages (matching iOS: sentBlobIds.contains || sentSequences.contains)
                            if (sentBlobIds.contains(event.id)) {
                                Log.d(TAG, "[$logId] Skipping own message (blobId match)")
                                return@collect
                            }
                            if (event.sequence != null && sentSequences.contains(event.sequence)) {
                                Log.d(TAG, "[$logId] Skipping own message (sequence match: ${event.sequence})")
                                sentBlobIds.add(event.id)
                                return@collect
                            }
                            // Filter duplicates
                            if (processedBlobIds.contains(event.id)) {
                                Log.d(TAG, "[$logId] Skipping duplicate message")
                                return@collect
                            }

                            Log.d(TAG, "[$logId] SSE processing: ${event.ciphertext.size} bytes, seq=${event.sequence}")

                            handleReceivedMessage(
                                ReceivedMessage(
                                    id = event.id,
                                    ciphertext = event.ciphertext,
                                    sequence = event.sequence,
                                    receivedAt = event.receivedAt
                                )
                            )
                            processedBlobIds.add(event.id)
                        }
                        is SSEEvent.DeliveryConfirmed -> {
                            Log.i(TAG, "[$logId] Delivery confirmed for ${event.blobIds.size} messages")
                            event.blobIds.forEach { blobId ->
                                handleDeliveryConfirmation(blobId)
                            }
                        }
                        is SSEEvent.BurnSignal -> {
                            Log.w(TAG, "[$logId] Peer burned conversation")
                            handlePeerBurn()
                        }
                        is SSEEvent.NotFound -> {
                            Log.w(TAG, "[$logId] Conversation not found on relay")
                            // Conversation not found on relay - try to register and reconnect
                            if (!hasAttemptedRegistration) {
                                hasAttemptedRegistration = true
                                if (registerConversationWithRelay(conv)) {
                                    // Retry SSE connection after successful registration
                                    startSSE(conv)
                                }
                            }
                        }
                        is SSEEvent.Error -> {
                            Log.e(TAG, "[$logId] SSE error: ${event.message}")
                        }
                        else -> { /* Ignore ping, disconnected */ }
                    }
                }
            }
    }

    private fun startPollingMessages() {
        pollingJob?.cancel()
        pollingJob =
            viewModelScope.launch {
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
            Log.d(TAG, "[$logId] Skipping duplicate (already in messages list)")
            return
        }

        // sequence is the sender's consumption offset, not absolute pad position
        val senderOffset =
            received.sequence ?: run {
                Log.w(TAG, "[$logId] Received message without sequence, skipping")
                return
            }

        // Check if this is our OWN sent message (matching iOS processReceivedMessage)
        // We must skip these to avoid corrupting peerConsumed state
        val isOwnMessage =
            when (conv.role) {
                ConversationRole.INITIATOR -> {
                    // Initiator sends from [0, sendOffset) - messages in this range are ours
                    senderOffset < conv.sendOffset
                }
                ConversationRole.RESPONDER -> {
                    // Responder sends from [totalBytes - sendOffset, totalBytes) - messages in this range are ours
                    senderOffset >= conv.padTotalSize - conv.sendOffset
                }
            }

        if (isOwnMessage) {
            Log.d(TAG, "[$logId] Skipping own sent message seq=$senderOffset (sendOffset=${conv.sendOffset})")
            return
        }

        // Check if we already processed this sequence (stored with conversation)
        if (conv.hasProcessedIncomingSequence(senderOffset)) {
            Log.d(TAG, "[$logId] Skipping already-processed message seq=$senderOffset")
            return
        }

        Log.d(TAG, "[$logId] Processing received message: ${received.ciphertext.size} bytes, seq=$senderOffset")

        try {
            // The sequence IS the absolute pad offset where the key starts
            // Matching iOS ReceiveMessageUseCase.swift:64-68: uses offset directly
            // - Initiator sends sequence = nextSendOffset() = absolute position from front
            // - Responder sends sequence = totalBytes - consumedBack - length = absolute position from back
            val absoluteOffset = senderOffset
            val peerRole: Role =
                if (conv.role == ConversationRole.INITIATOR) {
                    Role.RESPONDER
                } else {
                    Role.INITIATOR
                }

            Log.d(TAG, "[$logId] Decrypting: peerRole=$peerRole, absoluteOffset=$absoluteOffset")

            // Get key bytes from pad at the absolute position
            val keyBytes =
                padManager.getBytesForDecryption(
                    offset = absoluteOffset,
                    length = received.ciphertext.size,
                    conversationId = conversationId
                )

            // Decrypt using FFI
            val plaintext = ashCoreService.decrypt(keyBytes, received.ciphertext)

            val content = MessageContent.fromBytes(plaintext)
            val contentType =
                when (content) {
                    is MessageContent.Text -> "text"
                    is MessageContent.Location -> "location"
                }
            Log.i(TAG, "[$logId] Decrypted $contentType message, seq=$senderOffset")

            val disappearingSeconds = conv.disappearingMessages.seconds?.toLong()

            val message =
                Message.incoming(
                    conversationId = conversationId,
                    content = content,
                    sequence = senderOffset,
                    disappearingSeconds = disappearingSeconds,
                    blobId = received.id
                )

            _messages.value = _messages.value + message

            // Update peer consumption tracking using PadManager (Rust Pad state)
            // Calculation must match iOS's calculatePeerConsumed:
            // - If I'm initiator (peer is responder): peerConsumed = totalBytes - sequence
            // - If I'm responder (peer is initiator): peerConsumed = sequence + length
            val consumedAmount =
                if (conv.role == ConversationRole.INITIATOR) {
                    // Peer is responder (consumes backward from end)
                    conv.padTotalSize - senderOffset
                } else {
                    // Peer is initiator (consumes forward from start)
                    senderOffset + received.ciphertext.size
                }
            Log.d(TAG, "[$logId] Updating peer consumption: peerRole=$peerRole, consumed=$consumedAmount")
            padManager.updatePeerConsumption(peerRole, consumedAmount, conversationId)

            // Update conversation state (Kotlin entity) and persist to storage
            // This matches iOS's: conversation.afterReceiving + conversationRepository.save
            val updatedConv = conv.afterReceiving(senderOffset, received.ciphertext.size.toLong())
            conversationStorage.saveConversation(updatedConv)
            _conversation.value = updatedConv
            Log.d(TAG, "[$logId] Conversation state saved. Remaining=${updatedConv.remainingBytes}")

            // Send ACK
            sendAck(received.id)
        } catch (e: Exception) {
            Log.e(TAG, "[$logId] Failed to process message: ${e.message}", e)
        }
    }

    private fun handleDeliveryConfirmation(messageId: String) {
        _messages.value =
            _messages.value.map { msg ->
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
        val result =
            relayService.checkBurnStatus(
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
                    _error.value =
                        when (e) {
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

                // Calculate sequence (offset where key material STARTS)
                // Matching iOS SendMessageUseCase.swift:68-74
                // - Initiator: key starts at consumed_front (use nextSendOffset)
                // - Responder: key starts at total_size - consumed_back - message_size
                val sequence: Long =
                    if (myRole == Role.RESPONDER) {
                        val padState = padManager.getPadState(conversationId)
                        padState.totalBytes - padState.consumedBack - plaintext.size
                    } else {
                        padManager.nextSendOffset(myRole, conversationId)
                    }

                Log.i(
                    TAG,
                    "[$logId] Sending message: ${plaintext.size} bytes, seq=$sequence, remaining=${conv.remainingBytes}"
                )

                // Check if we can send
                if (!padManager.canSend(plaintext.size, myRole, conversationId)) {
                    Log.w(TAG, "[$logId] Pad exhausted - cannot send")
                    _error.value = "Pad exhausted - cannot send message"
                    return@launch
                }

                // Track sent sequence BEFORE sending to filter out SSE echoes (matching iOS)
                sentSequences.add(sequence)
                Log.d(TAG, "[$logId] Tracked sent sequence: $sequence, sentSequences now: $sentSequences")

                // Consume pad bytes for encryption (this updates state in PadManager)
                val keyBytes = padManager.consumeForSending(plaintext.size, myRole, conversationId)

                // Encrypt using FFI
                val ciphertext = ashCoreService.encrypt(keyBytes, plaintext)

                Log.d(TAG, "[$logId] Encrypted: ${plaintext.size} → ${ciphertext.size} bytes")

                // Update conversation state after sending and persist to storage
                // This matches iOS's: conversation.afterSending + conversationRepository.save
                val updatedConv = conv.afterSending(plaintext.size.toLong())
                conversationStorage.saveConversation(updatedConv)
                _conversation.value = updatedConv

                // Create message
                val message =
                    Message(
                        conversationId = conversationId,
                        content = content,
                        direction = MessageDirection.SENT,
                        status = DeliveryStatus.SENDING,
                        sequence = sequence,
                        serverExpiresAt = System.currentTimeMillis() + (conv.messageRetention.seconds * 1000L)
                    )

                // Add to local list immediately
                _messages.value = _messages.value + message

                // Send to relay (matching iOS: POST /v1/messages)
                val sendResult =
                    relayService.submitMessage(
                        conversationId = conversationId,
                        authToken = conv.authToken,
                        ciphertext = ciphertext,
                        sequence = sequence,
                        ttlSeconds = conv.messageRetention.seconds,
                        relayUrl = conv.relayUrl
                    )

                if (sendResult.success && sendResult.blobId != null) {
                    // Track sent blob ID to filter out SSE echoes (matching iOS)
                    sentBlobIds.add(sendResult.blobId)

                    // Update message with blob ID and status
                    _messages.value =
                        _messages.value.map {
                            if (it.id == message.id) {
                                it.withBlobId(sendResult.blobId).withDeliveryStatus(DeliveryStatus.SENT)
                            } else {
                                it
                            }
                        }
                    Log.i(TAG, "[$logId] Message sent: blobId=${sendResult.blobId.take(8)}")
                } else {
                    // Mark as failed
                    _messages.value =
                        _messages.value.map {
                            if (it.id == message.id) {
                                it.withDeliveryStatus(DeliveryStatus.FAILED(sendResult.error))
                            } else {
                                it
                            }
                        }
                    _error.value = sendResult.error ?: "Failed to send message"
                    Log.e(TAG, "[$logId] Send failed: ${sendResult.error}")
                }
            } catch (e: Exception) {
                _error.value = "Failed to send message: ${e.message}"
                Log.e(TAG, "[$logId] Send exception: ${e.message}", e)
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
