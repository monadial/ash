package com.monadial.ash.ui.screens

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.VideocamOff
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.monadial.ash.domain.entities.CeremonyError
import com.monadial.ash.domain.entities.CeremonyPhase
import com.monadial.ash.domain.entities.ConsentState
import com.monadial.ash.domain.entities.ConversationColor
import com.monadial.ash.domain.entities.DisappearingMessages
import com.monadial.ash.domain.entities.MessageRetention
import com.monadial.ash.domain.entities.PadSize
import com.monadial.ash.ui.components.EntropyCollectionView
import com.monadial.ash.ui.components.QRCodeFrameCounter
import com.monadial.ash.ui.components.QRCodeView
import com.monadial.ash.ui.components.QRScannerView
import com.monadial.ash.ui.components.ScanProgressOverlay
import com.monadial.ash.ui.theme.AshColors
import com.monadial.ash.ui.theme.AshCornerRadius
import com.monadial.ash.ui.theme.AshSpacing
import com.monadial.ash.ui.viewmodels.InitiatorCeremonyViewModel
import com.monadial.ash.ui.viewmodels.ReceiverCeremonyViewModel

/**
 * Ceremony Screen - 1:1 port from iOS
 * Handles the complete key exchange ceremony flow
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CeremonyScreen(
    onComplete: (String) -> Unit,
    onCancel: () -> Unit
) {
    var selectedRole by remember { mutableStateOf<CeremonyRole?>(null) }

    when (selectedRole) {
        null -> {
            RoleSelectionScreen(
                onRoleSelected = { role -> selectedRole = role },
                onCancel = onCancel
            )
        }
        CeremonyRole.INITIATOR -> {
            InitiatorCeremonyScreen(
                onComplete = onComplete,
                onCancel = { selectedRole = null }
            )
        }
        CeremonyRole.RECEIVER -> {
            ReceiverCeremonyScreen(
                onComplete = onComplete,
                onCancel = { selectedRole = null }
            )
        }
    }
}

enum class CeremonyRole {
    INITIATOR,
    RECEIVER
}

// MARK: - Role Selection Screen (matches iOS RoleSelectionView)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RoleSelectionScreen(
    onRoleSelected: (CeremonyRole) -> Unit,
    onCancel: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("New Conversation") },
                navigationIcon = {
                    IconButton(onClick = onCancel) {
                        Icon(Icons.Default.Close, contentDescription = "Cancel")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(AshSpacing.lg),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(AshSpacing.xl))

            Text(
                text = "Choose Your Role",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold
            )

            Spacer(modifier = Modifier.height(AshSpacing.sm))

            Text(
                text = "Both devices must be physically present to establish a secure channel.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(AshSpacing.xxl))

            // Create (Initiator) option
            RoleOptionCard(
                title = "Create",
                subtitle = "Generate a new one-time pad and display QR codes for your partner to scan.",
                icon = Icons.Default.QrCode2,
                iconTint = AshColors.ashAccent,
                onClick = { onRoleSelected(CeremonyRole.INITIATOR) }
            )

            Spacer(modifier = Modifier.height(AshSpacing.md))

            // Join (Receiver) option
            RoleOptionCard(
                title = "Join",
                subtitle = "Scan QR codes from your partner's device to receive the encryption pad.",
                icon = Icons.Default.CameraAlt,
                iconTint = AshColors.green,
                onClick = { onRoleSelected(CeremonyRole.RECEIVER) }
            )

            Spacer(modifier = Modifier.weight(1f))
        }
    }
}

@Composable
private fun RoleOptionCard(
    title: String,
    subtitle: String,
    icon: ImageVector,
    iconTint: Color,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        ),
        shape = RoundedCornerShape(AshCornerRadius.lg)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(AshSpacing.lg),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .clip(CircleShape)
                    .background(iconTint.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = iconTint,
                    modifier = Modifier.size(28.dp)
                )
            }

            Spacer(modifier = Modifier.width(AshSpacing.md))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.height(AshSpacing.xxs))
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

// MARK: - Initiator Ceremony Screen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun InitiatorCeremonyScreen(
    viewModel: InitiatorCeremonyViewModel = hiltViewModel(),
    onComplete: (String) -> Unit,
    onCancel: () -> Unit
) {
    val phase by viewModel.phase.collectAsState()
    val selectedPadSize by viewModel.selectedPadSize.collectAsState()
    val selectedColor by viewModel.selectedColor.collectAsState()
    val conversationName by viewModel.conversationName.collectAsState()
    val relayUrl by viewModel.relayUrl.collectAsState()
    val serverRetention by viewModel.serverRetention.collectAsState()
    val disappearingMessages by viewModel.disappearingMessages.collectAsState()
    val consent by viewModel.consent.collectAsState()
    val entropyProgress by viewModel.entropyProgress.collectAsState()
    val currentQRBitmap by viewModel.currentQRBitmap.collectAsState()
    val currentFrameIndex by viewModel.currentFrameIndex.collectAsState()
    val totalFrames by viewModel.totalFrames.collectAsState()
    val connectionTestResult by viewModel.connectionTestResult.collectAsState()
    val isTestingConnection by viewModel.isTestingConnection.collectAsState()

    val accentColor = Color(selectedColor.toColorLong())

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(getInitiatorTitle(phase)) },
                navigationIcon = {
                    IconButton(onClick = {
                        viewModel.cancel()
                        onCancel()
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        AnimatedContent(
            targetState = phase,
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            label = "ceremony_phase",
            // Use contentKey to prevent re-animation when only progress changes
            contentKey = { phaseToContentKey(it) }
        ) { currentPhase ->
            when (currentPhase) {
                is CeremonyPhase.SelectingPadSize -> {
                    PadSizeSelectionContent(
                        selectedSize = selectedPadSize,
                        onSizeSelected = viewModel::selectPadSize,
                        onProceed = viewModel::proceedToOptions,
                        accentColor = accentColor
                    )
                }

                is CeremonyPhase.ConfiguringOptions -> {
                    OptionsConfigurationContent(
                        conversationName = conversationName,
                        onNameChange = viewModel::setConversationName,
                        relayUrl = relayUrl,
                        onRelayUrlChange = viewModel::setRelayUrl,
                        selectedColor = selectedColor,
                        onColorChange = viewModel::setSelectedColor,
                        serverRetention = serverRetention,
                        onRetentionChange = viewModel::setServerRetention,
                        disappearingMessages = disappearingMessages,
                        onDisappearingChange = viewModel::setDisappearingMessages,
                        onTestConnection = viewModel::testRelayConnection,
                        isTestingConnection = isTestingConnection,
                        connectionTestResult = connectionTestResult,
                        onProceed = viewModel::proceedToConsent,
                        accentColor = accentColor
                    )
                }

                is CeremonyPhase.ConfirmingConsent -> {
                    ConsentContent(
                        consent = consent,
                        onConsentChange = viewModel::updateConsent,
                        onConfirm = viewModel::confirmConsent,
                        accentColor = accentColor
                    )
                }

                is CeremonyPhase.CollectingEntropy -> {
                    EntropyCollectionView(
                        progress = entropyProgress,
                        onPointCollected = viewModel::addEntropy,
                        accentColor = accentColor
                    )
                }

                is CeremonyPhase.GeneratingPad -> {
                    LoadingContent(
                        title = "Generating Pad",
                        message = "Creating your secure one-time pad..."
                    )
                }

                is CeremonyPhase.GeneratingQRCodes -> {
                    LoadingContent(
                        title = "Preparing Transfer",
                        message = "Generating QR codes...",
                        progress = currentPhase.progress
                    )
                }

                is CeremonyPhase.Transferring -> {
                    TransferringContent(
                        bitmap = currentQRBitmap,
                        currentFrame = currentFrameIndex,
                        totalFrames = totalFrames,
                        onDone = viewModel::finishSending,
                        accentColor = accentColor
                    )
                }

                is CeremonyPhase.Verifying -> {
                    VerificationContent(
                        mnemonic = currentPhase.mnemonic,
                        onConfirm = {
                            val conversation = viewModel.confirmVerification()
                            conversation?.let { onComplete(it.id) }
                        },
                        onReject = viewModel::rejectVerification,
                        accentColor = accentColor
                    )
                }

                is CeremonyPhase.Completed -> {
                    CompletedContent(
                        conversationId = currentPhase.conversation.id,
                        onDismiss = { onComplete(currentPhase.conversation.id) }
                    )
                }

                is CeremonyPhase.Failed -> {
                    FailedContent(
                        error = currentPhase.error,
                        onRetry = viewModel::reset,
                        onCancel = onCancel
                    )
                }

                else -> { /* Receiver phases not used here */ }
            }
        }
    }
}

// MARK: - Receiver Ceremony Screen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReceiverCeremonyScreen(
    viewModel: ReceiverCeremonyViewModel = hiltViewModel(),
    onComplete: (String) -> Unit,
    onCancel: () -> Unit
) {
    val phase by viewModel.phase.collectAsState()
    val conversationName by viewModel.conversationName.collectAsState()
    val receivedBlocks by viewModel.receivedBlocks.collectAsState()
    val totalBlocks by viewModel.totalBlocks.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(getReceiverTitle(phase)) },
                navigationIcon = {
                    IconButton(onClick = {
                        viewModel.cancel()
                        onCancel()
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        AnimatedContent(
            targetState = phase,
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            label = "receiver_ceremony_phase",
            // Use contentKey to prevent re-animation when only progress changes
            contentKey = { phaseToContentKey(it) }
        ) { currentPhase ->
            when (currentPhase) {
                is CeremonyPhase.ConfiguringReceiver -> {
                    ReceiverSetupContent(
                        conversationName = conversationName,
                        onNameChange = viewModel::setConversationName,
                        onStartScanning = viewModel::startScanning
                    )
                }

                is CeremonyPhase.Scanning, is CeremonyPhase.Transferring -> {
                    ScanningContent(
                        receivedBlocks = receivedBlocks,
                        totalBlocks = totalBlocks,
                        onFrameScanned = viewModel::processScannedFrame
                    )
                }

                is CeremonyPhase.Verifying -> {
                    VerificationContent(
                        mnemonic = currentPhase.mnemonic,
                        onConfirm = {
                            val conversation = viewModel.confirmVerification()
                            conversation?.let { onComplete(it.id) }
                        },
                        onReject = viewModel::rejectVerification,
                        accentColor = MaterialTheme.colorScheme.primary
                    )
                }

                is CeremonyPhase.Completed -> {
                    CompletedContent(
                        conversationId = currentPhase.conversation.id,
                        onDismiss = { onComplete(currentPhase.conversation.id) }
                    )
                }

                is CeremonyPhase.Failed -> {
                    FailedContent(
                        error = currentPhase.error,
                        onRetry = viewModel::reset,
                        onCancel = onCancel
                    )
                }

                else -> { /* Initiator phases not used here */ }
            }
        }
    }
}

// MARK: - Pad Size Selection (matches iOS PadSizeView)

@Composable
private fun PadSizeSelectionContent(
    selectedSize: PadSize,
    onSizeSelected: (PadSize) -> Unit,
    onProceed: () -> Unit,
    accentColor: Color
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(AshSpacing.lg),
        verticalArrangement = Arrangement.spacedBy(AshSpacing.md)
    ) {
        Text(
            text = "Choose Pad Size",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold
        )

        Text(
            text = "Larger pads support more messages but take longer to transfer.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(AshSpacing.md))

        PadSize.entries.forEach { size ->
            PadSizeCard(
                size = size,
                isSelected = size == selectedSize,
                onClick = { onSizeSelected(size) },
                accentColor = accentColor
            )
        }

        Spacer(modifier = Modifier.weight(1f))

        Button(
            onClick = onProceed,
            modifier = Modifier
                .fillMaxWidth()
                .height(50.dp),
            colors = ButtonDefaults.buttonColors(containerColor = accentColor),
            shape = RoundedCornerShape(AshCornerRadius.md)
        ) {
            Text("Continue", fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun PadSizeCard(
    size: PadSize,
    isSelected: Boolean,
    onClick: () -> Unit,
    accentColor: Color
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .then(
                if (isSelected) Modifier.border(2.dp, accentColor, RoundedCornerShape(AshCornerRadius.md))
                else Modifier
            ),
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected)
                accentColor.copy(alpha = 0.1f)
            else
                MaterialTheme.colorScheme.surfaceVariant
        ),
        shape = RoundedCornerShape(AshCornerRadius.md)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(AshSpacing.md),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = size.displayName,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = size.subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = "Transfer: ${size.transferTime}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                )
            }
            if (isSelected) {
                Icon(
                    Icons.Default.Check,
                    contentDescription = "Selected",
                    tint = accentColor
                )
            }
        }
    }
}

// MARK: - Options Configuration (matches iOS OptionsView)

@Composable
private fun OptionsConfigurationContent(
    conversationName: String,
    onNameChange: (String) -> Unit,
    relayUrl: String,
    onRelayUrlChange: (String) -> Unit,
    selectedColor: ConversationColor,
    onColorChange: (ConversationColor) -> Unit,
    serverRetention: MessageRetention,
    onRetentionChange: (MessageRetention) -> Unit,
    disappearingMessages: DisappearingMessages,
    onDisappearingChange: (DisappearingMessages) -> Unit,
    onTestConnection: () -> Unit,
    isTestingConnection: Boolean,
    connectionTestResult: InitiatorCeremonyViewModel.ConnectionTestResult?,
    onProceed: () -> Unit,
    accentColor: Color
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(AshSpacing.lg),
        verticalArrangement = Arrangement.spacedBy(AshSpacing.lg)
    ) {
        Text(
            text = "Conversation Settings",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold
        )

        // Conversation Name
        OutlinedTextField(
            value = conversationName,
            onValueChange = onNameChange,
            label = { Text("Conversation Name") },
            placeholder = { Text("Optional - give this conversation a name") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )

        // Color Selection
        Text(
            text = "Accent Color",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Medium
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(AshSpacing.xs),
            modifier = Modifier.fillMaxWidth()
        ) {
            ConversationColor.entries.take(5).forEach { color ->
                ColorDot(
                    color = Color(color.toColorLong()),
                    isSelected = color == selectedColor,
                    onClick = { onColorChange(color) }
                )
            }
        }
        Row(
            horizontalArrangement = Arrangement.spacedBy(AshSpacing.xs),
            modifier = Modifier.fillMaxWidth()
        ) {
            ConversationColor.entries.drop(5).forEach { color ->
                ColorDot(
                    color = Color(color.toColorLong()),
                    isSelected = color == selectedColor,
                    onClick = { onColorChange(color) }
                )
            }
        }

        // Relay URL
        OutlinedTextField(
            value = relayUrl,
            onValueChange = onRelayUrlChange,
            label = { Text("Relay Server") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )

        Row(
            horizontalArrangement = Arrangement.spacedBy(AshSpacing.xs),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedButton(
                onClick = onTestConnection,
                enabled = !isTestingConnection
            ) {
                if (isTestingConnection) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp
                    )
                } else {
                    Text("Test Connection")
                }
            }

            connectionTestResult?.let { result ->
                when (result) {
                    is InitiatorCeremonyViewModel.ConnectionTestResult.Success ->
                        Text("Connected", color = AshColors.ashSuccess)
                    is InitiatorCeremonyViewModel.ConnectionTestResult.Failure ->
                        Text("Failed: ${result.error}", color = AshColors.ashDanger)
                }
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        Button(
            onClick = onProceed,
            modifier = Modifier
                .fillMaxWidth()
                .height(50.dp),
            colors = ButtonDefaults.buttonColors(containerColor = accentColor),
            shape = RoundedCornerShape(AshCornerRadius.md)
        ) {
            Text("Continue", fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun ColorDot(
    color: Color,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .size(40.dp)
            .clip(CircleShape)
            .background(color)
            .clickable { onClick() }
            .then(
                if (isSelected) Modifier.border(3.dp, MaterialTheme.colorScheme.onSurface, CircleShape)
                else Modifier
            ),
        contentAlignment = Alignment.Center
    ) {
        if (isSelected) {
            Icon(
                Icons.Default.Check,
                contentDescription = "Selected",
                tint = Color.White,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

// MARK: - Consent Screen (matches iOS ConsentView with all 7 items)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ConsentContent(
    consent: ConsentState,
    onConsentChange: (ConsentState) -> Unit,
    onConfirm: () -> Unit,
    accentColor: Color
) {
    var showEthicsSheet by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(AshSpacing.lg),
        verticalArrangement = Arrangement.spacedBy(AshSpacing.sm)
    ) {
        Text(
            text = "Security Acknowledgment",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold
        )

        Text(
            text = "Please confirm you understand these critical security properties before proceeding.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(AshSpacing.md))

        // 1. Secure Environment
        ConsentItem(
            icon = Icons.Default.Shield,
            iconTint = AshColors.ashAccent,
            text = "I am in a secure environment where my screen cannot be observed",
            checked = consent.secureEnvironment,
            onCheckedChange = { onConsentChange(consent.copy(secureEnvironment = it)) }
        )

        // 2. No Surveillance
        ConsentItem(
            icon = Icons.Default.VideocamOff,
            iconTint = AshColors.ashDanger,
            text = "No cameras or screens are recording this ceremony",
            checked = consent.noSurveillance,
            onCheckedChange = { onConsentChange(consent.copy(noSurveillance = it)) }
        )

        // 3. Ethics Reviewed
        ConsentItem(
            icon = Icons.AutoMirrored.Filled.MenuBook,
            iconTint = AshColors.blue,
            text = "I have reviewed the ethics guidelines",
            checked = consent.ethicsReviewed,
            onCheckedChange = { onConsentChange(consent.copy(ethicsReviewed = it)) },
            actionText = "View Guidelines",
            onAction = { showEthicsSheet = true }
        )

        // 4. Key Loss Understanding
        ConsentItem(
            icon = Icons.Default.VpnKey,
            iconTint = AshColors.orange,
            text = "I understand that lost keys cannot be recovered - there is no \"forgot password\"",
            checked = consent.keyLossUnderstood,
            onCheckedChange = { onConsentChange(consent.copy(keyLossUnderstood = it)) }
        )

        // 5. Relay Warning
        ConsentItem(
            icon = Icons.Default.Storage,
            iconTint = AshColors.purple,
            text = "I understand that relay servers can see message timing and metadata",
            checked = consent.relayWarningUnderstood,
            onCheckedChange = { onConsentChange(consent.copy(relayWarningUnderstood = it)) }
        )

        // 6. Data Loss Accepted
        ConsentItem(
            icon = Icons.Default.Warning,
            iconTint = AshColors.ashWarning,
            text = "I accept responsibility for any data loss resulting from device loss or app deletion",
            checked = consent.dataLossAccepted,
            onCheckedChange = { onConsentChange(consent.copy(dataLossAccepted = it)) }
        )

        // 7. Burn Understanding
        ConsentItem(
            icon = Icons.Default.LocalFireDepartment,
            iconTint = AshColors.ashDanger,
            text = "I understand that \"Burn\" permanently destroys all conversation data",
            checked = consent.burnUnderstood,
            onCheckedChange = { onConsentChange(consent.copy(burnUnderstood = it)) }
        )

        Spacer(modifier = Modifier.weight(1f))

        Button(
            onClick = onConfirm,
            modifier = Modifier
                .fillMaxWidth()
                .height(50.dp),
            enabled = consent.allConfirmed,
            colors = ButtonDefaults.buttonColors(containerColor = accentColor),
            shape = RoundedCornerShape(AshCornerRadius.md)
        ) {
            Text("I Understand & Accept", fontWeight = FontWeight.SemiBold)
        }
    }

    // Ethics Guidelines Sheet
    if (showEthicsSheet) {
        ModalBottomSheet(
            onDismissRequest = { showEthicsSheet = false },
            sheetState = sheetState
        ) {
            EthicsGuidelinesContent(
                onDismiss = { showEthicsSheet = false }
            )
        }
    }
}

@Composable
private fun ConsentItem(
    icon: ImageVector,
    iconTint: Color,
    text: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    actionText: String? = null,
    onAction: (() -> Unit)? = null
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onCheckedChange(!checked) },
        colors = CardDefaults.cardColors(
            containerColor = if (checked)
                iconTint.copy(alpha = 0.1f)
            else
                MaterialTheme.colorScheme.surfaceVariant
        ),
        shape = RoundedCornerShape(AshCornerRadius.md)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(AshSpacing.md),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = iconTint,
                modifier = Modifier.size(24.dp)
            )

            Spacer(modifier = Modifier.width(AshSpacing.sm))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = text,
                    style = MaterialTheme.typography.bodyMedium
                )
                if (actionText != null && onAction != null) {
                    TextButton(
                        onClick = onAction,
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)
                    ) {
                        Text(actionText, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }

            Checkbox(
                checked = checked,
                onCheckedChange = onCheckedChange,
                colors = CheckboxDefaults.colors(
                    checkedColor = iconTint
                )
            )
        }
    }
}

// MARK: - Ethics Guidelines Sheet (matches iOS EthicsGuidelinesSheet)

@Composable
private fun EthicsGuidelinesContent(
    onDismiss: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(AshSpacing.lg)
    ) {
        Text(
            text = "Ethics Guidelines",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(AshSpacing.lg))

        EthicsItem(
            number = 1,
            title = "Lawful Use Only",
            description = "ASH is designed for legitimate privacy needs. Do not use it for any illegal activities, including but not limited to: planning crimes, evading law enforcement, or facilitating harm to others."
        )

        EthicsItem(
            number = 2,
            title = "No Exploitation",
            description = "Never use ASH to exploit, abuse, or harm vulnerable individuals. This includes but is not limited to: harassment, stalking, or any form of abuse."
        )

        EthicsItem(
            number = 3,
            title = "Responsible Communication",
            description = "Use ASH for genuine private communication needs. The strong encryption is meant to protect legitimate privacy, not to enable irresponsible behavior."
        )

        EthicsItem(
            number = 4,
            title = "Transparency with Partners",
            description = "Be honest with your communication partners about the nature of ASH. Ensure they understand the security model and the implications of key loss."
        )

        EthicsItem(
            number = 5,
            title = "Report Misuse",
            description = "If you become aware of ASH being used for harmful purposes, consider reporting it to appropriate authorities while respecting the privacy of innocent parties."
        )

        Spacer(modifier = Modifier.height(AshSpacing.lg))

        Button(
            onClick = onDismiss,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(AshCornerRadius.md)
        ) {
            Text("I Understand")
        }

        Spacer(modifier = Modifier.height(AshSpacing.xl))
    }
}

@Composable
private fun EthicsItem(
    number: Int,
    title: String,
    description: String
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = AshSpacing.sm)
    ) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primary),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = number.toString(),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onPrimary,
                fontWeight = FontWeight.Bold
            )
        }

        Spacer(modifier = Modifier.width(AshSpacing.sm))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

// MARK: - Loading Content

@Composable
private fun LoadingContent(
    title: String,
    message: String,
    progress: Float? = null
) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(AshSpacing.md)
        ) {
            if (progress != null) {
                CircularProgressIndicator(progress = { progress })
                Text("${(progress * 100).toInt()}%")
            } else {
                CircularProgressIndicator()
            }

            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )

            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

// MARK: - Transfer Content (matches iOS QRDisplayView)

@Composable
private fun TransferringContent(
    bitmap: android.graphics.Bitmap?,
    currentFrame: Int,
    totalFrames: Int,
    onDone: () -> Unit,
    accentColor: Color
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(AshSpacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(AshSpacing.lg)
    ) {
        Text(
            text = "Show QR Codes",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold
        )

        Text(
            text = "Hold your phone steady while your partner scans all the QR codes.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(AshSpacing.md))

        QRCodeView(bitmap = bitmap, size = 300.dp)

        QRCodeFrameCounter(
            currentFrame = currentFrame,
            totalFrames = totalFrames
        )

        Spacer(modifier = Modifier.weight(1f))

        Button(
            onClick = onDone,
            modifier = Modifier
                .fillMaxWidth()
                .height(50.dp),
            colors = ButtonDefaults.buttonColors(containerColor = accentColor),
            shape = RoundedCornerShape(AshCornerRadius.md)
        ) {
            Text("Partner Finished Scanning", fontWeight = FontWeight.SemiBold)
        }
    }
}

// MARK: - Scanning Content (matches iOS QRScanView)

@Composable
private fun ScanningContent(
    receivedBlocks: Int,
    totalBlocks: Int,
    onFrameScanned: (String) -> Unit
) {
    Box(modifier = Modifier.fillMaxSize()) {
        QRScannerView(
            onQRCodeScanned = onFrameScanned,
            modifier = Modifier.fillMaxSize()
        )

        ScanProgressOverlay(
            receivedBlocks = receivedBlocks,
            totalBlocks = totalBlocks,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(AshSpacing.lg)
        )
    }
}

// MARK: - Receiver Setup Content (matches iOS ReceiverSetupView)

@Composable
private fun ReceiverSetupContent(
    conversationName: String,
    onNameChange: (String) -> Unit,
    onStartScanning: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(AshSpacing.lg),
        verticalArrangement = Arrangement.spacedBy(AshSpacing.lg)
    ) {
        Text(
            text = "Join Conversation",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold
        )

        Text(
            text = "Point your camera at the QR codes on your partner's screen. The transfer will happen automatically.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        OutlinedTextField(
            value = conversationName,
            onValueChange = onNameChange,
            label = { Text("Conversation Name") },
            placeholder = { Text("Optional - give this conversation a name") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )

        Spacer(modifier = Modifier.weight(1f))

        Button(
            onClick = onStartScanning,
            modifier = Modifier
                .fillMaxWidth()
                .height(50.dp),
            shape = RoundedCornerShape(AshCornerRadius.md)
        ) {
            Icon(
                Icons.Default.CameraAlt,
                contentDescription = null,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(AshSpacing.xs))
            Text("Start Scanning", fontWeight = FontWeight.SemiBold)
        }
    }
}

// MARK: - Verification Content (matches iOS VerificationView)

@Composable
private fun VerificationContent(
    mnemonic: List<String>,
    onConfirm: () -> Unit,
    onReject: () -> Unit,
    accentColor: Color
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(AshSpacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(AshSpacing.lg)
    ) {
        Icon(
            Icons.Default.Security,
            contentDescription = null,
            tint = accentColor,
            modifier = Modifier.size(48.dp)
        )

        Text(
            text = "Verify Checksum",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold
        )

        Text(
            text = "Read these words aloud with your partner. They must match exactly on both devices.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(AshSpacing.lg))

        // Mnemonic display - two rows of 3 words
        Column(
            verticalArrangement = Arrangement.spacedBy(AshSpacing.sm)
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(AshSpacing.xs),
                modifier = Modifier.fillMaxWidth()
            ) {
                mnemonic.take(3).forEachIndexed { index, word ->
                    MnemonicWord(
                        index = index + 1,
                        word = word,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
            Row(
                horizontalArrangement = Arrangement.spacedBy(AshSpacing.xs),
                modifier = Modifier.fillMaxWidth()
            ) {
                mnemonic.drop(3).take(3).forEachIndexed { index, word ->
                    MnemonicWord(
                        index = index + 4,
                        word = word,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        Row(
            horizontalArrangement = Arrangement.spacedBy(AshSpacing.md),
            modifier = Modifier.fillMaxWidth()
        ) {
            OutlinedButton(
                onClick = onReject,
                modifier = Modifier
                    .weight(1f)
                    .height(50.dp),
                colors = ButtonDefaults.outlinedButtonColors(
                    contentColor = AshColors.ashDanger
                ),
                shape = RoundedCornerShape(AshCornerRadius.md)
            ) {
                Text("No Match", fontWeight = FontWeight.SemiBold)
            }
            Button(
                onClick = onConfirm,
                modifier = Modifier
                    .weight(1f)
                    .height(50.dp),
                colors = ButtonDefaults.buttonColors(containerColor = AshColors.ashSuccess),
                shape = RoundedCornerShape(AshCornerRadius.md)
            ) {
                Text("Words Match", fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun MnemonicWord(
    index: Int,
    word: String,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        ),
        shape = RoundedCornerShape(AshCornerRadius.sm)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(AshSpacing.sm),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = index.toString(),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = word,
                style = MaterialTheme.typography.bodyLarge,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

// MARK: - Completed Content (matches iOS CompletedView)

@Composable
private fun CompletedContent(
    conversationId: String,
    onDismiss: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(AshSpacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            modifier = Modifier
                .size(100.dp)
                .clip(CircleShape)
                .background(AshColors.ashSuccess),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.Default.Check,
                contentDescription = "Success",
                tint = Color.White,
                modifier = Modifier.size(56.dp)
            )
        }

        Spacer(modifier = Modifier.height(AshSpacing.xl))

        Text(
            text = "Ceremony Complete",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(AshSpacing.sm))

        Text(
            text = "Your secure channel has been established. You can now exchange encrypted messages.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(AshSpacing.xxl))

        Button(
            onClick = onDismiss,
            modifier = Modifier
                .fillMaxWidth()
                .height(50.dp),
            shape = RoundedCornerShape(AshCornerRadius.md)
        ) {
            Text("Start Messaging", fontWeight = FontWeight.SemiBold)
        }
    }
}

// MARK: - Failed Content (matches iOS FailedView)

@Composable
private fun FailedContent(
    error: CeremonyError,
    onRetry: () -> Unit,
    onCancel: () -> Unit
) {
    val (errorTitle, errorMessage) = when (error) {
        CeremonyError.CANCELLED -> "Ceremony Cancelled" to "The ceremony was cancelled before completion."
        CeremonyError.QR_GENERATION_FAILED -> "QR Generation Failed" to "Failed to generate QR codes. Please try again."
        CeremonyError.PAD_RECONSTRUCTION_FAILED -> "Transfer Failed" to "Could not reconstruct the encryption pad. Please try again."
        CeremonyError.CHECKSUM_MISMATCH -> "Verification Failed" to "The checksum words did not match. This may indicate tampering or transmission errors."
        CeremonyError.PASSPHRASE_MISMATCH -> "Passphrase Mismatch" to "The passphrase did not match. Please verify with your partner."
        CeremonyError.INVALID_FRAME -> "Invalid Data" to "Received invalid QR code data. Please try scanning again."
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(AshSpacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            modifier = Modifier
                .size(100.dp)
                .clip(CircleShape)
                .background(AshColors.ashDanger),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.Default.Close,
                contentDescription = "Error",
                tint = Color.White,
                modifier = Modifier.size(56.dp)
            )
        }

        Spacer(modifier = Modifier.height(AshSpacing.xl))

        Text(
            text = errorTitle,
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(AshSpacing.sm))

        Text(
            text = errorMessage,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(AshSpacing.xxl))

        Row(
            horizontalArrangement = Arrangement.spacedBy(AshSpacing.md),
            modifier = Modifier.fillMaxWidth()
        ) {
            OutlinedButton(
                onClick = onCancel,
                modifier = Modifier
                    .weight(1f)
                    .height(50.dp),
                shape = RoundedCornerShape(AshCornerRadius.md)
            ) {
                Text("Cancel", fontWeight = FontWeight.SemiBold)
            }
            Button(
                onClick = onRetry,
                modifier = Modifier
                    .weight(1f)
                    .height(50.dp),
                shape = RoundedCornerShape(AshCornerRadius.md)
            ) {
                Text("Try Again", fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

// MARK: - Helpers

/**
 * Returns a stable key for each phase type, so that AnimatedContent
 * doesn't re-animate when only the progress/frame values change within a phase.
 */
private fun phaseToContentKey(phase: CeremonyPhase): String = when (phase) {
    is CeremonyPhase.SelectingRole -> "selecting_role"
    is CeremonyPhase.SelectingPadSize -> "selecting_pad_size"
    is CeremonyPhase.ConfiguringOptions -> "configuring_options"
    is CeremonyPhase.ConfirmingConsent -> "confirming_consent"
    is CeremonyPhase.CollectingEntropy -> "collecting_entropy"
    is CeremonyPhase.GeneratingPad -> "generating_pad"
    is CeremonyPhase.GeneratingQRCodes -> "generating_qr_codes"  // Same key regardless of progress
    is CeremonyPhase.Transferring -> "transferring"  // Same key regardless of frame
    is CeremonyPhase.Verifying -> "verifying"
    is CeremonyPhase.Completed -> "completed"
    is CeremonyPhase.Failed -> "failed"
    is CeremonyPhase.ConfiguringReceiver -> "configuring_receiver"
    is CeremonyPhase.Scanning -> "scanning"
}

private fun getInitiatorTitle(phase: CeremonyPhase): String = when (phase) {
    is CeremonyPhase.SelectingPadSize -> "Pad Size"
    is CeremonyPhase.ConfiguringOptions -> "Settings"
    is CeremonyPhase.ConfirmingConsent -> "Acknowledgment"
    is CeremonyPhase.CollectingEntropy -> "Generate Entropy"
    is CeremonyPhase.GeneratingPad -> "Generating"
    is CeremonyPhase.GeneratingQRCodes -> "Preparing"
    is CeremonyPhase.Transferring -> "Transfer"
    is CeremonyPhase.Verifying -> "Verify"
    is CeremonyPhase.Completed -> "Complete"
    is CeremonyPhase.Failed -> "Failed"
    else -> "Create"
}

private fun getReceiverTitle(phase: CeremonyPhase): String = when (phase) {
    is CeremonyPhase.ConfiguringReceiver -> "Setup"
    is CeremonyPhase.Scanning, is CeremonyPhase.Transferring -> "Scanning"
    is CeremonyPhase.Verifying -> "Verify"
    is CeremonyPhase.Completed -> "Complete"
    is CeremonyPhase.Failed -> "Failed"
    else -> "Join"
}
