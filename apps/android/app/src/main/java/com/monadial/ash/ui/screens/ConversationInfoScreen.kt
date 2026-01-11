package com.monadial.ash.ui.screens

import androidx.compose.foundation.background
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
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.entities.ConversationRole
import com.monadial.ash.ui.viewmodels.ConversationInfoViewModel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Suppress("UnusedParameter")
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConversationInfoScreen(
    conversationId: String,
    onBack: () -> Unit,
    onBurned: () -> Unit,
    viewModel: ConversationInfoViewModel = hiltViewModel()
) {
    val conversation by viewModel.conversation.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val isBurning by viewModel.isBurning.collectAsState()
    val burned by viewModel.burned.collectAsState()

    var showBurnDialog by remember { mutableStateOf(false) }
    var showRenameDialog by remember { mutableStateOf(false) }

    LaunchedEffect(burned) {
        if (burned) {
            onBurned()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Conversation Info") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        if (isLoading) {
            Box(
                modifier =
                Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
        } else {
            conversation?.let { conv ->
                val accentColor = Color(conv.color.toColorLong())

                Column(
                    modifier =
                    Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp)
                ) {
                    // Avatar and name header
                    ConversationHeader(
                        conversation = conv,
                        accentColor = accentColor,
                        onRenameClick = { showRenameDialog = true }
                    )

                    Spacer(modifier = Modifier.height(24.dp))

                    // Mnemonic verification
                    MnemonicCard(conv.mnemonic)

                    Spacer(modifier = Modifier.height(16.dp))

                    // Pad usage
                    PadUsageCard(conv, accentColor)

                    Spacer(modifier = Modifier.height(16.dp))

                    // Details
                    DetailsCard(conv)

                    Spacer(modifier = Modifier.height(16.dp))

                    // Message settings
                    MessageSettingsCard(conv)

                    Spacer(modifier = Modifier.height(32.dp))

                    // Burn button
                    BurnButton(
                        isBurning = isBurning,
                        onClick = { showBurnDialog = true }
                    )
                }
            }
        }
    }

    // Burn confirmation dialog
    if (showBurnDialog) {
        AlertDialog(
            onDismissRequest = { showBurnDialog = false },
            icon = {
                Icon(
                    Icons.Default.LocalFireDepartment,
                    contentDescription = null,
                    tint = Color(0xFFFF3B30)
                )
            },
            title = { Text("Burn Conversation?") },
            text = {
                Text(
                    "This will permanently destroy the encryption pad and all messages. " +
                        "Your peer will be notified. This action cannot be undone."
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        showBurnDialog = false
                        viewModel.burnConversation()
                    },
                    colors =
                    ButtonDefaults.buttonColors(
                        containerColor = Color(0xFFFF3B30)
                    )
                ) {
                    Text("Burn")
                }
            },
            dismissButton = {
                TextButton(onClick = { showBurnDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Rename dialog
    if (showRenameDialog) {
        var newName by remember { mutableStateOf(conversation?.name ?: "") }
        AlertDialog(
            onDismissRequest = { showRenameDialog = false },
            title = { Text("Rename Conversation") },
            text = {
                OutlinedTextField(
                    value = newName,
                    onValueChange = { newName = it },
                    label = { Text("Name") },
                    placeholder = { Text(conversation?.mnemonic?.take(3)?.joinToString(" ") ?: "") },
                    singleLine = true
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        viewModel.renameConversation(newName.ifBlank { null })
                        showRenameDialog = false
                    }
                ) {
                    Text("Save")
                }
            },
            dismissButton = {
                TextButton(onClick = { showRenameDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
private fun ConversationHeader(conversation: Conversation, accentColor: Color, onRenameClick: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier =
            Modifier
                .size(80.dp)
                .clip(CircleShape)
                .background(accentColor),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = conversation.avatarInitials,
                style = MaterialTheme.typography.headlineMedium,
                color = Color.White,
                fontWeight = FontWeight.Bold
            )
        }

        Spacer(modifier = Modifier.height(12.dp))

        Text(
            text = conversation.displayName,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold
        )

        TextButton(onClick = onRenameClick) {
            Text("Rename")
        }
    }
}

@Composable
private fun MnemonicCard(mnemonic: List<String>) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors =
        CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.VpnKey,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Verification Words",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = mnemonic.joinToString(" "),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Verify these words match on both devices",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun PadUsageCard(conversation: Conversation, accentColor: Color) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors =
        CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.Storage,
                    contentDescription = null,
                    tint = accentColor
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Encryption Pad",
                    style = MaterialTheme.typography.titleSmall,
                    color = accentColor
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Usage bar
            DualUsageBar(
                myUsage = conversation.myUsagePercentage.toFloat(),
                peerUsage = conversation.peerUsagePercentage.toFloat(),
                accentColor = accentColor
            )

            Spacer(modifier = Modifier.height(12.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column {
                    Text(
                        text = "Remaining",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = conversation.formattedRemaining,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = "Total Size",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = formatBytes(conversation.padTotalSize),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                UsageLegendItem(
                    color = accentColor,
                    label = "You",
                    percentage = conversation.myUsagePercentage
                )
                UsageLegendItem(
                    color = accentColor.copy(alpha = 0.5f),
                    label = "Peer",
                    percentage = conversation.peerUsagePercentage
                )
            }
        }
    }
}

@Composable
private fun DualUsageBar(myUsage: Float, peerUsage: Float, accentColor: Color) {
    Box(
        modifier =
        Modifier
            .fillMaxWidth()
            .height(12.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
    ) {
        // My usage from left
        Box(
            modifier =
            Modifier
                .fillMaxWidth(myUsage / 100f)
                .height(12.dp)
                .background(accentColor)
                .align(Alignment.CenterStart)
        )
        // Peer usage from right
        Box(
            modifier =
            Modifier
                .fillMaxWidth(peerUsage / 100f)
                .height(12.dp)
                .background(accentColor.copy(alpha = 0.5f))
                .align(Alignment.CenterEnd)
        )
    }
}

@Composable
private fun UsageLegendItem(color: Color, label: String, percentage: Double) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier =
            Modifier
                .size(12.dp)
                .clip(CircleShape)
                .background(color)
        )
        Spacer(modifier = Modifier.width(6.dp))
        Text(
            text = "$label: ${percentage.toInt()}%",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun DetailsCard(conversation: Conversation) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors =
        CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Details",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary
            )

            Spacer(modifier = Modifier.height(12.dp))

            DetailRow("Conversation ID", conversation.id.take(16) + "...")
            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
            DetailRow("Role", if (conversation.role == ConversationRole.INITIATOR) "Initiator" else "Responder")
            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
            DetailRow("Created", formatDate(conversation.createdAt))
            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
            DetailRow("Relay Server", conversation.relayUrl)
        }
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium
        )
    }
}

@Composable
private fun MessageSettingsCard(conversation: Conversation) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors =
        CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Message Settings",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary
            )

            Spacer(modifier = Modifier.height(12.dp))

            InfoRow(
                icon = Icons.Default.Schedule,
                label = "Server Retention",
                value = conversation.messageRetention.displayName
            )

            Spacer(modifier = Modifier.height(8.dp))

            InfoRow(
                icon = Icons.Default.Timer,
                label = "Disappearing Messages",
                value = conversation.disappearingMessages.displayName
            )

            if (conversation.persistenceConsent) {
                Spacer(modifier = Modifier.height(8.dp))
                InfoRow(
                    icon = Icons.Default.Visibility,
                    label = "Message Persistence",
                    value = "Enabled"
                )
            }
        }
    }
}

@Composable
private fun InfoRow(icon: ImageVector, label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            icon,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f)
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium
        )
    }
}

@Composable
private fun BurnButton(isBurning: Boolean, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = !isBurning,
        modifier = Modifier.fillMaxWidth(),
        colors =
        ButtonDefaults.buttonColors(
            containerColor = Color(0xFFFF3B30)
        ),
        shape = RoundedCornerShape(12.dp)
    ) {
        if (isBurning) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                color = Color.White,
                strokeWidth = 2.dp
            )
            Spacer(modifier = Modifier.width(8.dp))
        }
        Icon(
            Icons.Default.LocalFireDepartment,
            contentDescription = null
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(if (isBurning) "Burning..." else "Burn Conversation")
    }
}

private fun formatBytes(bytes: Long): String {
    return when {
        bytes >= 1024 * 1024 -> "%.1f MB".format(bytes / (1024.0 * 1024.0))
        bytes >= 1024 -> "%.1f KB".format(bytes / 1024.0)
        else -> "$bytes B"
    }
}

private fun formatDate(timestamp: Long): String {
    val sdf = SimpleDateFormat("MMM d, yyyy 'at' HH:mm", Locale.getDefault())
    return sdf.format(Date(timestamp))
}
