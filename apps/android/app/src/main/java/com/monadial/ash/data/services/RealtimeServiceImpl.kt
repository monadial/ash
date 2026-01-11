package com.monadial.ash.data.services

import com.monadial.ash.core.services.SSEConnectionState
import com.monadial.ash.core.services.SSEEvent
import com.monadial.ash.core.services.SSEService
import com.monadial.ash.domain.services.RealtimeService
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Implementation of RealtimeService that delegates to SSEService.
 * Provides real-time message streaming via Server-Sent Events.
 */
@Singleton
class RealtimeServiceImpl @Inject constructor(
    private val sseService: SSEService
) : RealtimeService {

    override val connectionState: StateFlow<SSEConnectionState>
        get() = sseService.connectionState

    override val events: SharedFlow<SSEEvent>
        get() = sseService.events

    override fun connect(relayUrl: String, conversationId: String, authToken: String) {
        sseService.connect(relayUrl, conversationId, authToken)
    }

    override fun disconnect() {
        sseService.disconnect()
    }

    override fun isConnectedTo(conversationId: String): Boolean {
        return sseService.isConnectedTo(conversationId)
    }

    override fun currentConversationId(): String? {
        // SSEService doesn't expose this directly, but we can infer from isConnectedTo
        // For now, return null as we don't have direct access
        return null
    }
}
