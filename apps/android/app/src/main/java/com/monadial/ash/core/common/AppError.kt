package com.monadial.ash.core.common

import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/**
 * Sealed hierarchy of application errors.
 * Provides type-safe error handling across all layers.
 */
sealed class AppError(
    open val message: String,
    open val cause: Throwable? = null
) {
    fun toException(): Exception = AppException(this)

    // Network errors
    sealed class Network(
        override val message: String,
        override val cause: Throwable? = null
    ) : AppError(message, cause) {
        data class ConnectionFailed(
            override val message: String = "Connection failed",
            override val cause: Throwable? = null
        ) : Network(message, cause)

        data class Timeout(
            override val message: String = "Request timed out",
            override val cause: Throwable? = null
        ) : Network(message, cause)

        data class NoInternet(
            override val message: String = "No internet connection",
            override val cause: Throwable? = null
        ) : Network(message, cause)

        data class ServerError(
            val code: Int,
            override val message: String
        ) : Network(message)

        data class HttpError(
            val code: Int,
            override val message: String
        ) : Network(message)
    }

    // Relay-specific errors
    sealed class Relay(override val message: String) : AppError(message) {
        data object ConversationNotFound : Relay("Conversation not found on relay")
        data object Unauthorized : Relay("Unauthorized access")
        data object ConversationBurned : Relay("Conversation has been burned")
        data object RegistrationFailed : Relay("Failed to register conversation")
        data class SubmitFailed(override val message: String) : Relay(message)
    }

    // Pad/encryption errors
    sealed class Pad(override val message: String) : AppError(message) {
        data object Exhausted : Pad("Pad is exhausted - no more bytes available")
        data object NotFound : Pad("Pad not found for conversation")
        data object InvalidState : Pad("Pad is in an invalid state")
        data class ConsumptionFailed(override val message: String) : Pad(message)
    }

    // Cryptography errors
    sealed class Crypto(
        override val message: String,
        override val cause: Throwable? = null
    ) : AppError(message, cause) {
        data class EncryptionFailed(
            override val message: String = "Encryption failed",
            override val cause: Throwable? = null
        ) : Crypto(message, cause)

        data class DecryptionFailed(
            override val message: String = "Decryption failed",
            override val cause: Throwable? = null
        ) : Crypto(message, cause)

        data class TokenDerivationFailed(
            override val message: String = "Failed to derive tokens",
            override val cause: Throwable? = null
        ) : Crypto(message, cause)
    }

    // Storage errors
    sealed class Storage(
        override val message: String,
        override val cause: Throwable? = null
    ) : AppError(message, cause) {
        data class ReadFailed(
            override val message: String = "Failed to read from storage",
            override val cause: Throwable? = null
        ) : Storage(message, cause)

        data class WriteFailed(
            override val message: String = "Failed to write to storage",
            override val cause: Throwable? = null
        ) : Storage(message, cause)

        data class NotFound(
            override val message: String = "Data not found in storage"
        ) : Storage(message)
    }

    // Location errors
    sealed class Location(override val message: String) : AppError(message) {
        data object PermissionDenied : Location("Location permission denied")
        data object Unavailable : Location("Location unavailable")
        data object Timeout : Location("Location request timed out")
    }

    // Ceremony errors
    sealed class Ceremony(override val message: String) : AppError(message) {
        data object QRGenerationFailed : Ceremony("Failed to generate QR code")
        data object PadReconstructionFailed : Ceremony("Failed to reconstruct pad from QR codes")
        data object ChecksumMismatch : Ceremony("Checksum mismatch - pads do not match")
        data object Cancelled : Ceremony("Ceremony was cancelled")
        data object InvalidFrame : Ceremony("Invalid QR frame received")
    }

    // Generic errors
    data class Unknown(
        override val message: String,
        override val cause: Throwable? = null
    ) : AppError(message, cause)

    data class Validation(
        override val message: String
    ) : AppError(message)

    companion object {
        fun fromException(throwable: Throwable): AppError = when (throwable) {
            is AppException -> throwable.error
            is SocketTimeoutException -> Network.Timeout(cause = throwable)
            is UnknownHostException -> Network.NoInternet(cause = throwable)
            is IOException -> Network.ConnectionFailed(throwable.message ?: "IO error", throwable)
            else -> Unknown(throwable.message ?: "Unknown error", throwable)
        }
    }
}

/**
 * Exception wrapper for AppError to allow throwing in contexts that require exceptions.
 */
class AppException(val error: AppError) : Exception(error.message, error.cause)
