package com.monadial.ash.domain.services

import com.monadial.ash.core.services.SSEConnectionState
import com.monadial.ash.core.services.SSEEvent
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Interface for real-time messaging via Server-Sent Events.
 * Abstracts SSE connection management for testability.
 */
interface RealtimeService {

    /**
     * Observable connection state.
     */
    val connectionState: StateFlow<SSEConnectionState>

    /**
     * Observable event stream.
     */
    val events: SharedFlow<SSEEvent>

    /**
     * Connect to the SSE stream for a conversation.
     *
     * @param relayUrl The relay server URL
     * @param conversationId The conversation ID
     * @param authToken The auth token for authentication
     */
    fun connect(relayUrl: String, conversationId: String, authToken: String)

    /**
     * Disconnect from the current SSE stream.
     */
    fun disconnect()

    /**
     * Check if currently connected to a specific conversation.
     */
    fun isConnectedTo(conversationId: String): Boolean

    /**
     * Get the currently connected conversation ID, if any.
     */
    fun currentConversationId(): String?
}
