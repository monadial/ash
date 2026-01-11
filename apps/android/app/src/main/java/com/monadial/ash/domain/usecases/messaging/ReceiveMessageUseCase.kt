package com.monadial.ash.domain.usecases.messaging

import android.util.Log
import com.monadial.ash.core.common.AppError
import com.monadial.ash.core.common.AppResult
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.entities.ConversationRole
import com.monadial.ash.domain.entities.Message
import com.monadial.ash.domain.entities.MessageContent
import com.monadial.ash.domain.repositories.ConversationRepository
import com.monadial.ash.domain.repositories.PadRepository
import com.monadial.ash.domain.services.CryptoService
import javax.inject.Inject

private const val TAG = "ReceiveMessageUseCase"

/**
 * Input data for receiving a message.
 */
data class ReceivedMessageData(
    val id: String,
    val ciphertext: ByteArray,
    val sequence: Long?,
    val receivedAt: String
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as ReceivedMessageData
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}

/**
 * Result of processing a received message.
 */
sealed class ReceiveMessageResult {
    data class Success(
        val message: Message,
        val updatedConversation: Conversation
    ) : ReceiveMessageResult()

    data class Skipped(val reason: String) : ReceiveMessageResult()
    data class Error(val error: AppError) : ReceiveMessageResult()
}

/**
 * Use case for receiving and decrypting messages.
 *
 * Encapsulates the receive flow:
 * 1. Validate sequence number
 * 2. Check for own message / already processed
 * 3. Get key bytes for decryption
 * 4. Decrypt ciphertext using OTP
 * 5. Parse message content
 * 6. Update peer consumption state
 * 7. Update conversation state
 *
 * This follows Single Responsibility Principle by handling only message receiving.
 */
class ReceiveMessageUseCase @Inject constructor(
    private val conversationRepository: ConversationRepository,
    private val padRepository: PadRepository,
    private val cryptoService: CryptoService
) {

    /**
     * Process a received encrypted message.
     *
     * @param conversation The conversation this message belongs to
     * @param received The received message data (ciphertext, sequence, etc.)
     * @return Result containing the decrypted message and updated conversation, or skip/error
     */
    suspend operator fun invoke(
        conversation: Conversation,
        received: ReceivedMessageData
    ): ReceiveMessageResult {
        val logId = conversation.id.take(8)

        // 1. Validate sequence
        val senderOffset = received.sequence
        if (senderOffset == null) {
            Log.w(TAG, "[$logId] Received message without sequence, skipping")
            return ReceiveMessageResult.Skipped("No sequence number")
        }

        // 2. Check if this is our OWN sent message (must skip to avoid corrupting peerConsumed)
        val isOwnMessage = when (conversation.role) {
            ConversationRole.INITIATOR -> {
                // Initiator sends from [0, sendOffset) - messages in this range are ours
                senderOffset < conversation.sendOffset
            }
            ConversationRole.RESPONDER -> {
                // Responder sends from [totalBytes - sendOffset, totalBytes)
                senderOffset >= conversation.padTotalSize - conversation.sendOffset
            }
        }

        if (isOwnMessage) {
            Log.d(TAG, "[$logId] Skipping own sent message seq=$senderOffset")
            return ReceiveMessageResult.Skipped("Own message echo")
        }

        // 3. Check if already processed
        if (conversation.hasProcessedIncomingSequence(senderOffset)) {
            Log.d(TAG, "[$logId] Skipping already-processed message seq=$senderOffset")
            return ReceiveMessageResult.Skipped("Already processed")
        }

        Log.d(TAG, "[$logId] Processing: ${received.ciphertext.size} bytes, seq=$senderOffset")

        // 4. Get key bytes for decryption (does NOT update consumption state)
        val keyBytesResult = padRepository.getBytesForDecryption(
            conversation.id,
            senderOffset,
            received.ciphertext.size
        )
        val keyBytes = when (keyBytesResult) {
            is AppResult.Error -> {
                Log.e(TAG, "[$logId] Failed to get key bytes: ${keyBytesResult.error.message}")
                return ReceiveMessageResult.Error(keyBytesResult.error)
            }
            is AppResult.Success -> keyBytesResult.data
        }

        // 5. Decrypt
        val plaintext = try {
            cryptoService.decrypt(keyBytes, received.ciphertext)
        } catch (e: Exception) {
            Log.e(TAG, "[$logId] Decryption failed: ${e.message}")
            return ReceiveMessageResult.Error(AppError.Crypto.DecryptionFailed("Decryption failed: ${e.message}", e))
        }

        // 6. Parse content
        val content = try {
            MessageContent.fromBytes(plaintext)
        } catch (e: Exception) {
            Log.e(TAG, "[$logId] Failed to parse message content: ${e.message}")
            return ReceiveMessageResult.Error(AppError.Validation("Invalid message format"))
        }

        val contentType = when (content) {
            is MessageContent.Text -> "text"
            is MessageContent.Location -> "location"
        }
        Log.i(TAG, "[$logId] Decrypted $contentType message, seq=$senderOffset")

        // 7. Update peer consumption tracking
        // - If I'm initiator (peer is responder): peerConsumed = totalBytes - sequence
        // - If I'm responder (peer is initiator): peerConsumed = sequence + length
        val peerRole = if (conversation.role == ConversationRole.INITIATOR) {
            ConversationRole.RESPONDER
        } else {
            ConversationRole.INITIATOR
        }

        val consumedAmount = if (conversation.role == ConversationRole.INITIATOR) {
            conversation.padTotalSize - senderOffset
        } else {
            senderOffset + received.ciphertext.size
        }

        Log.d(TAG, "[$logId] Updating peer consumption: peerRole=$peerRole, consumed=$consumedAmount")
        padRepository.updatePeerConsumption(conversation.id, peerRole, consumedAmount)

        // 8. Update conversation state and persist
        val updatedConv = conversation.afterReceiving(senderOffset, received.ciphertext.size.toLong())
        conversationRepository.saveConversation(updatedConv)
        Log.d(TAG, "[$logId] Conversation state saved. Remaining=${updatedConv.remainingBytes}")

        // 9. Create message entity
        val disappearingSeconds = conversation.disappearingMessages.seconds?.toLong()
        val message = Message.incoming(
            conversationId = conversation.id,
            content = content,
            sequence = senderOffset,
            disappearingSeconds = disappearingSeconds,
            blobId = received.id
        )

        return ReceiveMessageResult.Success(message, updatedConv)
    }
}
