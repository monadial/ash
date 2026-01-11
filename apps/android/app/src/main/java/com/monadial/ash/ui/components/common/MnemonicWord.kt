package com.monadial.ash.ui.components.common

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Displays a numbered mnemonic word for verification.
 *
 * @param number The word number (1-6)
 * @param word The mnemonic word
 * @param accentColor The color for the word text
 * @param modifier Optional modifier
 */
@Composable
fun MnemonicWord(
    number: Int,
    word: String,
    accentColor: Color = Color(0xFF5856D6),
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = "$number.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(24.dp)
        )
        Text(
            text = word,
            style = MaterialTheme.typography.titleMedium,
            color = accentColor
        )
    }
}
