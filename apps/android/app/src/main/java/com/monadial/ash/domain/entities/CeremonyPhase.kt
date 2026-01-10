package com.monadial.ash.domain.entities

sealed class CeremonyPhase {
    // Role selection (shared)
    data object SelectingRole : CeremonyPhase()

    // Initiator phases
    data object SelectingPadSize : CeremonyPhase()
    data object ConfiguringOptions : CeremonyPhase()
    data object ConfirmingConsent : CeremonyPhase()
    data object CollectingEntropy : CeremonyPhase()
    data object GeneratingPad : CeremonyPhase()
    data class GeneratingQRCodes(val progress: Float, val total: Int) : CeremonyPhase()
    data class Transferring(val currentFrame: Int, val totalFrames: Int) : CeremonyPhase()
    data class Verifying(val mnemonic: List<String>) : CeremonyPhase()
    data class Completed(val conversation: Conversation) : CeremonyPhase()
    data class Failed(val error: CeremonyError) : CeremonyPhase()

    // Receiver phases
    data object ConfiguringReceiver : CeremonyPhase()
    data object Scanning : CeremonyPhase()
}

enum class CeremonyError {
    CANCELLED,
    QR_GENERATION_FAILED,
    PAD_RECONSTRUCTION_FAILED,
    CHECKSUM_MISMATCH,
    PASSPHRASE_MISMATCH,
    INVALID_FRAME
}

enum class PadSize(val bytes: Long, val displayName: String, val subtitle: String) {
    SMALL(64 * 1024L, "64 KB", "100+ messages"),
    MEDIUM(256 * 1024L, "256 KB", "500+ messages"),
    LARGE(1024 * 1024L, "1 MB", "2000+ messages");

    val messageEstimate: Int
        get() = when (this) {
            SMALL -> 100
            MEDIUM -> 500
            LARGE -> 2000
        }

    val transferTime: String
        get() = when (this) {
            SMALL -> "~15 seconds"
            MEDIUM -> "~45 seconds"
            LARGE -> "~2 minutes"
        }
}

data class ConsentState(
    val secureEnvironment: Boolean = false,
    val noSurveillance: Boolean = false,
    val ethicsReviewed: Boolean = false,
    val keyLossUnderstood: Boolean = false,
    val relayWarningUnderstood: Boolean = false,
    val dataLossAccepted: Boolean = false,
    val burnUnderstood: Boolean = false
) {
    val allConfirmed: Boolean get() = secureEnvironment && noSurveillance && ethicsReviewed &&
            keyLossUnderstood && relayWarningUnderstood && dataLossAccepted && burnUnderstood
}
