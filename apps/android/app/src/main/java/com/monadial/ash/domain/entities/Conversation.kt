package com.monadial.ash.domain.entities

import kotlinx.serialization.Serializable

@Serializable
data class Conversation(
    val id: String,
    val name: String? = null,
    val relayUrl: String,
    val authToken: String,
    val burnToken: String,
    val role: ConversationRole,
    val color: ConversationColor = ConversationColor.INDIGO,
    val createdAt: Long,
    val lastMessageAt: Long? = null,
    val lastMessagePreview: String? = null,
    val unreadCount: Int = 0,
    // Pad state - bidirectional consumption
    val padConsumedFront: Long = 0,  // Bytes consumed by initiator (from start)
    val padConsumedBack: Long = 0,   // Bytes consumed by responder (from end)
    val padTotalSize: Long = 0,
    val mnemonic: List<String> = emptyList(),
    // Message settings
    val messageRetention: MessageRetention = MessageRetention.FIVE_MINUTES,
    val disappearingMessages: DisappearingMessages = DisappearingMessages.OFF,
    // Notification preferences (encoded in ceremony)
    val notifyNewMessage: Boolean = true,
    val notifyMessageExpiring: Boolean = false,
    val notifyMessageExpired: Boolean = false,
    val notifyDeliveryFailed: Boolean = true,
    // Persistence
    val persistenceConsent: Boolean = false,
    // Relay state
    val relayCursor: String? = null,
    val activitySequence: Long = 0,
    // Burn state
    val peerBurnedAt: Long? = null,
    // Deduplication - track processed incoming sequences
    val processedIncomingSequences: Set<Long> = emptySet()
) {
    // Computed properties
    val sendOffset: Long
        get() = if (role == ConversationRole.INITIATOR) padConsumedFront else padConsumedBack

    val peerConsumed: Long
        get() = if (role == ConversationRole.INITIATOR) padConsumedBack else padConsumedFront

    val remainingBytes: Long
        get() = padTotalSize - padConsumedFront - padConsumedBack

    val usagePercentage: Double
        get() = if (padTotalSize > 0) {
            ((padConsumedFront + padConsumedBack).toDouble() / padTotalSize) * 100
        } else 0.0

    val myUsagePercentage: Double
        get() = if (padTotalSize > 0) {
            (sendOffset.toDouble() / padTotalSize) * 100
        } else 0.0

    val peerUsagePercentage: Double
        get() = if (padTotalSize > 0) {
            (peerConsumed.toDouble() / padTotalSize) * 100
        } else 0.0

    val isExhausted: Boolean
        get() = remainingBytes <= 0

    val isBurned: Boolean
        get() = peerBurnedAt != null

    val allowsMessagePersistence: Boolean
        get() = disappearingMessages.isEnabled && persistenceConsent

    val displayName: String
        get() = name ?: mnemonic.take(3).joinToString(" ")

    val avatarInitials: String
        get() {
            val displayText = displayName
            val words = displayText.split(" ")
            return when {
                words.size >= 2 -> "${words[0].firstOrNull()?.uppercase() ?: ""}${words[1].firstOrNull()?.uppercase() ?: ""}"
                displayText.length >= 2 -> displayText.take(2).uppercase()
                else -> displayText.uppercase()
            }
        }

    val formattedRemaining: String
        get() = formatBytes(remainingBytes)

    fun canSendMessage(length: Int): Boolean {
        return remainingBytes >= length
    }

    fun hasProcessedIncomingSequence(sequence: Long): Boolean {
        return sequence in processedIncomingSequences
    }

    fun renamed(newName: String?): Conversation = copy(name = newName)

    fun withRelayUrl(url: String): Conversation = copy(relayUrl = url)

    fun withAccentColor(color: ConversationColor): Conversation = copy(color = color)

    fun withCursor(cursor: String?): Conversation = copy(relayCursor = cursor)

    fun withProcessedSequence(sequence: Long): Conversation = copy(
        processedIncomingSequences = processedIncomingSequences + sequence
    )

    fun afterSending(bytes: Long): Conversation {
        return if (role == ConversationRole.INITIATOR) {
            copy(padConsumedFront = padConsumedFront + bytes)
        } else {
            copy(padConsumedBack = padConsumedBack + bytes)
        }
    }

    fun afterReceiving(sequence: Long, length: Long): Conversation {
        // Update peer's consumption based on role
        val newPeerConsumed = if (role == ConversationRole.INITIATOR) {
            // Peer is responder, consuming from back
            // sequence is start offset from end
            maxOf(padConsumedBack, padTotalSize - sequence)
        } else {
            // Peer is initiator, consuming from front
            maxOf(padConsumedFront, sequence + length)
        }

        return if (role == ConversationRole.INITIATOR) {
            copy(
                padConsumedBack = newPeerConsumed,
                processedIncomingSequences = processedIncomingSequences + sequence
            )
        } else {
            copy(
                padConsumedFront = newPeerConsumed,
                processedIncomingSequences = processedIncomingSequences + sequence
            )
        }
    }

    companion object {
        private fun formatBytes(bytes: Long): String {
            return when {
                bytes >= 1024 * 1024 -> "%.1f MB".format(bytes / (1024.0 * 1024.0))
                bytes >= 1024 -> "%.1f KB".format(bytes / 1024.0)
                else -> "$bytes B"
            }
        }
    }
}

@Serializable
enum class ConversationRole {
    INITIATOR,
    RESPONDER;

    val peerRole: ConversationRole
        get() = if (this == INITIATOR) RESPONDER else INITIATOR
}

@Serializable
enum class ConversationColor {
    INDIGO,
    BLUE,
    PURPLE,
    TEAL,
    GREEN,
    CYAN,
    MINT,
    ORANGE,
    PINK,
    BROWN;

    fun toColorLong(): Long = when (this) {
        INDIGO -> 0xFF5856D6
        BLUE -> 0xFF007AFF
        PURPLE -> 0xFFAF52DE
        TEAL -> 0xFF30B0C7
        GREEN -> 0xFF34C759
        CYAN -> 0xFF32ADE6
        MINT -> 0xFF00C7BE
        ORANGE -> 0xFFFF9500
        PINK -> 0xFFFF2D55
        BROWN -> 0xFFA2845E
    }

    val displayName: String
        get() = name.lowercase().replaceFirstChar { it.uppercase() }

    companion object {
        fun fromIndex(index: Int): ConversationColor {
            return entries.getOrElse(index) { INDIGO }
        }
    }
}

@Serializable
enum class MessageRetention(val seconds: Long, val displayName: String, val shortName: String) {
    FIVE_MINUTES(300, "5 minutes", "5m"),
    ONE_HOUR(3600, "1 hour", "1h"),
    TWELVE_HOURS(43200, "12 hours", "12h"),
    ONE_DAY(86400, "1 day", "1d"),
    SEVEN_DAYS(604800, "7 days", "7d");

    companion object {
        fun fromSeconds(seconds: Long): MessageRetention {
            return entries.find { it.seconds == seconds } ?: FIVE_MINUTES
        }
    }
}

@Serializable
enum class DisappearingMessages(val seconds: Int?, val displayName: String) {
    OFF(null, "Off"),
    THIRTY_SECONDS(30, "30 seconds"),
    FIVE_MINUTES(300, "5 minutes"),
    TEN_MINUTES(600, "10 minutes"),
    THIRTY_MINUTES(1800, "30 minutes"),
    ONE_HOUR(3600, "1 hour");

    val isEnabled: Boolean
        get() = seconds != null

    companion object {
        fun fromSeconds(seconds: Int?): DisappearingMessages {
            if (seconds == null || seconds == 0) return OFF
            return entries.find { it.seconds == seconds } ?: OFF
        }
    }
}
