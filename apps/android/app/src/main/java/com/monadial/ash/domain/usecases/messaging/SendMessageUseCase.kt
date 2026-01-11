package com.monadial.ash.domain.usecases.messaging

import android.util.Log
import com.monadial.ash.core.common.AppError
import com.monadial.ash.core.common.AppResult
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.entities.ConversationRole
import com.monadial.ash.domain.entities.DeliveryStatus
import com.monadial.ash.domain.entities.Message
import com.monadial.ash.domain.entities.MessageContent
import com.monadial.ash.domain.entities.MessageDirection
import com.monadial.ash.domain.repositories.ConversationRepository
import com.monadial.ash.domain.repositories.PadRepository
import com.monadial.ash.domain.services.CryptoService
import com.monadial.ash.domain.services.RelayService
import javax.inject.Inject

private const val TAG = "SendMessageUseCase"

/**
 * Result of a successful message send operation.
 */
data class SendMessageResult(
    val message: Message,
    val blobId: String,
    val sequence: Long
)

/**
 * Use case for sending encrypted messages.
 *
 * Encapsulates the entire send flow:
 * 1. Validate pad availability
 * 2. Calculate sequence number
 * 3. Consume pad bytes for encryption
 * 4. Encrypt plaintext using OTP
 * 5. Submit to relay server
 * 6. Update conversation state
 *
 * This follows Single Responsibility Principle by handling only message sending.
 */
class SendMessageUseCase @Inject constructor(
    private val conversationRepository: ConversationRepository,
    private val padRepository: PadRepository,
    private val cryptoService: CryptoService,
    private val relayService: RelayService
) {

    /**
     * Send a message in a conversation.
     *
     * @param conversation The conversation to send in
     * @param content The message content (text or location)
     * @return Result containing the sent message with blob ID, or an error
     */
    suspend operator fun invoke(
        conversation: Conversation,
        content: MessageContent
    ): AppResult<SendMessageResult> {
        val logId = conversation.id.take(8)
        val plaintext = MessageContent.toBytes(content)

        Log.d(TAG, "[$logId] Sending message: ${plaintext.size} bytes")

        // 1. Check if we can send
        val canSendResult = padRepository.canSend(conversation.id, plaintext.size, conversation.role)
        when (canSendResult) {
            is AppResult.Error -> return canSendResult
            is AppResult.Success -> {
                if (!canSendResult.data) {
                    Log.w(TAG, "[$logId] Pad exhausted - cannot send")
                    return AppResult.Error(AppError.Pad.Exhausted)
                }
            }
        }

        // 2. Calculate sequence (offset where key material STARTS)
        // - Initiator: key starts at consumed_front (nextSendOffset)
        // - Responder: key starts at total_size - consumed_back - message_size
        val sequenceResult = if (conversation.role == ConversationRole.RESPONDER) {
            padRepository.getPadState(conversation.id).let { stateResult ->
                when (stateResult) {
                    is AppResult.Error -> return stateResult
                    is AppResult.Success -> {
                        val padState = stateResult.data
                        AppResult.Success(padState.totalBytes - padState.consumedBack - plaintext.size)
                    }
                }
            }
        } else {
            padRepository.nextSendOffset(conversation.id, conversation.role)
        }

        val sequence = when (sequenceResult) {
            is AppResult.Error -> return sequenceResult
            is AppResult.Success -> sequenceResult.data
        }

        Log.d(TAG, "[$logId] Sequence=$sequence, remaining=${conversation.remainingBytes}")

        // 3. Consume pad bytes for encryption (updates state)
        val keyBytesResult = padRepository.consumeForSending(
            conversation.id,
            plaintext.size,
            conversation.role
        )
        val keyBytes = when (keyBytesResult) {
            is AppResult.Error -> return keyBytesResult
            is AppResult.Success -> keyBytesResult.data
        }

        // 4. Encrypt using OTP
        val ciphertext = cryptoService.encrypt(keyBytes, plaintext)
        Log.d(TAG, "[$logId] Encrypted: ${plaintext.size} → ${ciphertext.size} bytes")

        // 5. Update conversation state after sending
        val updatedConv = conversation.afterSending(plaintext.size.toLong())
        val saveResult = conversationRepository.saveConversation(updatedConv)
        if (saveResult is AppResult.Error) {
            Log.e(TAG, "[$logId] Failed to save conversation state")
            // Continue anyway - message sending is more important
        }

        // 6. Send to relay
        val sendResult = relayService.submitMessage(
            conversationId = conversation.id,
            authToken = conversation.authToken,
            ciphertext = ciphertext,
            sequence = sequence,
            ttlSeconds = conversation.messageRetention.seconds,
            relayUrl = conversation.relayUrl
        )

        return when (sendResult) {
            is AppResult.Error -> {
                Log.e(TAG, "[$logId] Send failed: ${sendResult.error.message}")
                sendResult
            }
            is AppResult.Success -> {
                val blobId = sendResult.data.blobId
                if (blobId == null) {
                    Log.e(TAG, "[$logId] Send succeeded but no blob ID returned")
                    return AppResult.Error(AppError.Relay.SubmitFailed("No blob ID returned"))
                }

                Log.i(TAG, "[$logId] Message sent: blobId=${blobId.take(8)}")

                val message = Message(
                    conversationId = conversation.id,
                    content = content,
                    direction = MessageDirection.SENT,
                    status = DeliveryStatus.SENT,
                    sequence = sequence,
                    blobId = blobId,
                    serverExpiresAt = System.currentTimeMillis() + (conversation.messageRetention.seconds * 1000L)
                )

                AppResult.Success(SendMessageResult(message, blobId, sequence))
            }
        }
    }
}
