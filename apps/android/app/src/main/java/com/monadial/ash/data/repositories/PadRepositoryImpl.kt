package com.monadial.ash.data.repositories

import com.monadial.ash.core.common.AppError
import com.monadial.ash.core.common.AppResult
import com.monadial.ash.core.services.PadManager
import com.monadial.ash.core.services.PadState
import com.monadial.ash.domain.entities.ConversationRole
import com.monadial.ash.domain.repositories.PadRepository
import uniffi.ash.Role
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Implementation of PadRepository using PadManager.
 * Provides a clean interface for pad operations.
 */
@Singleton
class PadRepositoryImpl @Inject constructor(
    private val padManager: PadManager
) : PadRepository {

    override suspend fun storePad(conversationId: String, padBytes: ByteArray): AppResult<Unit> {
        return try {
            padManager.storePad(padBytes, conversationId)
            AppResult.Success(Unit)
        } catch (e: Exception) {
            AppResult.Error(AppError.Pad.ConsumptionFailed("Failed to store pad: ${e.message}"))
        }
    }

    override suspend fun getPadBytes(conversationId: String): AppResult<ByteArray> {
        return try {
            val bytes = padManager.getPadBytes(conversationId)
            AppResult.Success(bytes)
        } catch (e: IllegalStateException) {
            AppResult.Error(AppError.Pad.NotFound)
        } catch (e: Exception) {
            AppResult.Error(AppError.Pad.ConsumptionFailed("Failed to get pad bytes: ${e.message}"))
        }
    }

    override suspend fun getPadState(conversationId: String): AppResult<PadState> {
        return try {
            val state = padManager.getPadState(conversationId)
            AppResult.Success(state)
        } catch (e: IllegalStateException) {
            AppResult.Error(AppError.Pad.NotFound)
        } catch (e: Exception) {
            AppResult.Error(AppError.Pad.ConsumptionFailed("Failed to get pad state: ${e.message}"))
        }
    }

    override suspend fun canSend(
        conversationId: String,
        length: Int,
        role: ConversationRole
    ): AppResult<Boolean> {
        return try {
            val canSend = padManager.canSend(length, role.toFfiRole(), conversationId)
            AppResult.Success(canSend)
        } catch (e: IllegalStateException) {
            AppResult.Error(AppError.Pad.NotFound)
        } catch (e: Exception) {
            AppResult.Error(AppError.Pad.ConsumptionFailed("Failed to check send availability: ${e.message}"))
        }
    }

    override suspend fun availableForSending(
        conversationId: String,
        role: ConversationRole
    ): AppResult<Long> {
        return try {
            val available = padManager.availableForSending(role.toFfiRole(), conversationId)
            AppResult.Success(available)
        } catch (e: IllegalStateException) {
            AppResult.Error(AppError.Pad.NotFound)
        } catch (e: Exception) {
            AppResult.Error(AppError.Pad.ConsumptionFailed("Failed to get available bytes: ${e.message}"))
        }
    }

    override suspend fun nextSendOffset(
        conversationId: String,
        role: ConversationRole
    ): AppResult<Long> {
        return try {
            val offset = padManager.nextSendOffset(role.toFfiRole(), conversationId)
            AppResult.Success(offset)
        } catch (e: IllegalStateException) {
            AppResult.Error(AppError.Pad.NotFound)
        } catch (e: Exception) {
            AppResult.Error(AppError.Pad.ConsumptionFailed("Failed to get next send offset: ${e.message}"))
        }
    }

    override suspend fun consumeForSending(
        conversationId: String,
        length: Int,
        role: ConversationRole
    ): AppResult<ByteArray> {
        return try {
            val keyBytes = padManager.consumeForSending(length, role.toFfiRole(), conversationId)
            AppResult.Success(keyBytes)
        } catch (e: IllegalStateException) {
            if (e.message?.contains("not found") == true) {
                AppResult.Error(AppError.Pad.NotFound)
            } else {
                AppResult.Error(AppError.Pad.Exhausted)
            }
        } catch (e: Exception) {
            AppResult.Error(AppError.Pad.ConsumptionFailed("Failed to consume pad: ${e.message}"))
        }
    }

    override suspend fun getBytesForDecryption(
        conversationId: String,
        offset: Long,
        length: Int
    ): AppResult<ByteArray> {
        return try {
            val bytes = padManager.getBytesForDecryption(offset, length, conversationId)
            AppResult.Success(bytes)
        } catch (e: IllegalStateException) {
            if (e.message?.contains("not found") == true) {
                AppResult.Error(AppError.Pad.NotFound)
            } else {
                AppResult.Error(AppError.Pad.InvalidState)
            }
        } catch (e: Exception) {
            AppResult.Error(AppError.Pad.ConsumptionFailed("Failed to get decryption bytes: ${e.message}"))
        }
    }

    override suspend fun updatePeerConsumption(
        conversationId: String,
        peerRole: ConversationRole,
        consumed: Long
    ): AppResult<Unit> {
        return try {
            padManager.updatePeerConsumption(peerRole.toFfiRole(), consumed, conversationId)
            AppResult.Success(Unit)
        } catch (e: IllegalStateException) {
            AppResult.Error(AppError.Pad.NotFound)
        } catch (e: Exception) {
            AppResult.Error(AppError.Pad.ConsumptionFailed("Failed to update peer consumption: ${e.message}"))
        }
    }

    override suspend fun zeroPadBytes(
        conversationId: String,
        offset: Long,
        length: Int
    ): AppResult<Unit> {
        return try {
            padManager.zeroPadBytes(offset, length, conversationId)
            AppResult.Success(Unit)
        } catch (e: Exception) {
            AppResult.Error(AppError.Pad.ConsumptionFailed("Failed to zero pad bytes: ${e.message}"))
        }
    }

    override suspend fun wipePad(conversationId: String): AppResult<Unit> {
        return try {
            padManager.wipePad(conversationId)
            AppResult.Success(Unit)
        } catch (e: Exception) {
            AppResult.Error(AppError.Pad.ConsumptionFailed("Failed to wipe pad: ${e.message}"))
        }
    }

    override fun invalidateCache(conversationId: String) {
        padManager.invalidateCache(conversationId)
    }

    override fun clearCache() {
        padManager.clearCache()
    }

    private fun ConversationRole.toFfiRole(): Role = when (this) {
        ConversationRole.INITIATOR -> Role.INITIATOR
        ConversationRole.RESPONDER -> Role.RESPONDER
    }
}
