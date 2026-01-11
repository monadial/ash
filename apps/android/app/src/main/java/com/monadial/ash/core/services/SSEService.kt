package com.monadial.ash.core.services

import android.util.Log
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

sealed class SSEEvent {
    /** New message received (matching iOS SSEMessageEvent) */
    data class MessageReceived(val id: String, val sequence: Long?, val ciphertext: ByteArray, val receivedAt: String) :
        SSEEvent() {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (javaClass != other?.javaClass) return false
            other as MessageReceived
            return id == other.id && ciphertext.contentEquals(other.ciphertext)
        }

        override fun hashCode(): Int = id.hashCode()
    }

    /** Delivery confirmation (matching iOS SSEDeliveredEvent) */
    data class DeliveryConfirmed(val blobIds: List<String>, val deliveredAt: String) : SSEEvent()

    data class BurnSignal(val burnedAt: String) : SSEEvent()

    data object Ping : SSEEvent()

    data class Error(val message: String) : SSEEvent()

    /** Conversation not found on relay - needs registration */
    data object NotFound : SSEEvent()

    data object Connected : SSEEvent()

    data object Disconnected : SSEEvent()
}

enum class SSEConnectionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    RECONNECTING
}

// Raw SSE event (matching iOS RawSSEEvent)
@Serializable
private data class RawSSEEvent(
    val type: String,
    val id: String? = null,
    val sequence: Long? = null,
    val ciphertext: String? = null,
    val received_at: String? = null,
    val burned_at: String? = null,
    val blob_ids: List<String>? = null,
    val delivered_at: String? = null
)

@Singleton
class SSEService @Inject constructor() {
    companion object {
        private const val TAG = "SSEService"
        private const val INITIAL_RETRY_DELAY_MS = 1000L
        private const val MAX_RETRY_DELAY_MS = 30000L
        private const val MAX_RETRY_ATTEMPTS = 10
    }

    private val scope = CoroutineScope(Dispatchers.IO)
    private val json = Json { ignoreUnknownKeys = true }

    private val _connectionState = MutableStateFlow(SSEConnectionState.DISCONNECTED)
    val connectionState: StateFlow<SSEConnectionState> = _connectionState.asStateFlow()

    private val _events = MutableSharedFlow<SSEEvent>(extraBufferCapacity = 64)
    val events: SharedFlow<SSEEvent> = _events.asSharedFlow()

    private var connectionJob: Job? = null
    private var currentConversationId: String? = null
    private var currentRelayUrl: String? = null
    private var currentAuthToken: String? = null
    private var retryAttempts = 0

    fun connect(relayUrl: String, conversationId: String, authToken: String) {
        // Disconnect existing connection if different conversation
        if (currentConversationId != conversationId) {
            disconnect()
        }

        currentRelayUrl = relayUrl
        currentConversationId = conversationId
        currentAuthToken = authToken
        retryAttempts = 0

        startConnection()
    }

    private fun startConnection() {
        connectionJob?.cancel()
        connectionJob =
            scope.launch {
                connectInternal()
            }
    }

    private suspend fun connectInternal() {
        val relayUrl = currentRelayUrl ?: return
        val conversationId = currentConversationId ?: return
        val authToken = currentAuthToken ?: return

        _connectionState.value = SSEConnectionState.CONNECTING

        var connection: HttpURLConnection? = null
        try {
            // URL format matching iOS: {baseURL}/v1/messages/stream?conversation_id={conversationId}
            val url = URL("$relayUrl/v1/messages/stream?conversation_id=$conversationId")
            Log.d(TAG, "Connecting to SSE: $url")
            connection =
                withContext(Dispatchers.IO) {
                    (url.openConnection() as HttpURLConnection).apply {
                        requestMethod = "GET"
                        setRequestProperty("Authorization", "Bearer $authToken")
                        setRequestProperty("Accept", "text/event-stream")
                        setRequestProperty("Cache-Control", "no-cache")
                        connectTimeout = 10000
                        readTimeout = 0 // No timeout for SSE
                        doInput = true
                    }
                }

            val responseCode = connection.responseCode
            if (responseCode == HttpURLConnection.HTTP_NOT_FOUND) {
                // Conversation not registered on relay - emit NotFound event
                Log.w(TAG, "SSE connection returned 404 - conversation not found on relay")
                _events.emit(SSEEvent.NotFound)
                _connectionState.value = SSEConnectionState.DISCONNECTED
                return // Don't retry automatically - let caller handle registration
            }
            if (responseCode != HttpURLConnection.HTTP_OK) {
                throw java.io.IOException("SSE connection failed with code: $responseCode")
            }

            _connectionState.value = SSEConnectionState.CONNECTED
            _events.emit(SSEEvent.Connected)
            retryAttempts = 0

            val reader = BufferedReader(InputStreamReader(connection.inputStream))
            var eventType = ""
            val dataBuilder = StringBuilder()

            while (scope.isActive) {
                val line =
                    withContext(Dispatchers.IO) {
                        reader.readLine()
                    } ?: break

                when {
                    line.startsWith("event:") -> {
                        eventType = line.removePrefix("event:").trim()
                    }
                    line.startsWith("data:") -> {
                        dataBuilder.append(line.removePrefix("data:").trim())
                    }
                    line.isEmpty() && dataBuilder.isNotEmpty() -> {
                        // End of event
                        processEvent(eventType, dataBuilder.toString())
                        eventType = ""
                        dataBuilder.clear()
                    }
                }
            }
        } catch (e: CancellationException) {
            Log.d(TAG, "SSE connection cancelled")
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "SSE connection error", e)
            _events.emit(SSEEvent.Error(e.message ?: "Unknown error"))
        } finally {
            connection?.disconnect()
            _connectionState.value = SSEConnectionState.DISCONNECTED
            _events.emit(SSEEvent.Disconnected)
        }

        // Attempt reconnection with exponential backoff
        if (scope.isActive && retryAttempts < MAX_RETRY_ATTEMPTS) {
            retryAttempts++
            val delayMs =
                minOf(
                    INITIAL_RETRY_DELAY_MS * (1 shl (retryAttempts - 1)),
                    MAX_RETRY_DELAY_MS
                )
            Log.d(TAG, "Reconnecting in ${delayMs}ms (attempt $retryAttempts)")
            _connectionState.value = SSEConnectionState.RECONNECTING
            delay(delayMs)
            connectInternal()
        }
    }

    private suspend fun processEvent(eventType: String, data: String) {
        try {
            // Parse as RawSSEEvent (matching iOS)
            val rawEvent = json.decodeFromString<RawSSEEvent>(data)

            when (rawEvent.type) {
                "message" -> {
                    val id = rawEvent.id
                    val ciphertextBase64 = rawEvent.ciphertext
                    val receivedAt = rawEvent.received_at

                    if (id != null && ciphertextBase64 != null && receivedAt != null) {
                        val ciphertext =
                            android.util.Base64.decode(
                                ciphertextBase64,
                                android.util.Base64.DEFAULT
                            )
                        Log.d(TAG, "Received message: ${ciphertext.size} bytes, seq=${rawEvent.sequence ?: 0}")
                        _events.emit(
                            SSEEvent.MessageReceived(
                                id = id,
                                sequence = rawEvent.sequence,
                                ciphertext = ciphertext,
                                receivedAt = receivedAt
                            )
                        )
                    }
                }
                "delivered" -> {
                    val blobIds = rawEvent.blob_ids
                    val deliveredAt = rawEvent.delivered_at

                    if (blobIds != null && deliveredAt != null) {
                        Log.d(TAG, "Received delivery confirmation for ${blobIds.size} messages")
                        _events.emit(SSEEvent.DeliveryConfirmed(blobIds, deliveredAt))
                    }
                }
                "burned" -> {
                    val burnedAt = rawEvent.burned_at
                    if (burnedAt != null) {
                        Log.w(TAG, "Received burn event")
                        _events.emit(SSEEvent.BurnSignal(burnedAt))
                    }
                }
                "ping" -> {
                    _events.emit(SSEEvent.Ping)
                }
                else -> {
                    Log.w(TAG, "Unknown event type: ${rawEvent.type}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing SSE event: $eventType", e)
        }
    }

    fun disconnect() {
        connectionJob?.cancel()
        connectionJob = null
        currentConversationId = null
        currentRelayUrl = null
        currentAuthToken = null
        _connectionState.value = SSEConnectionState.DISCONNECTED
    }

    fun isConnected(): Boolean = _connectionState.value == SSEConnectionState.CONNECTED

    fun isConnectedTo(conversationId: String): Boolean = isConnected() && currentConversationId == conversationId
}
