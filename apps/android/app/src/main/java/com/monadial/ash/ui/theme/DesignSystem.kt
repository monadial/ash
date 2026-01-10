package com.monadial.ash.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * ASH Design System - matching iOS design tokens
 */
object AshSpacing {
    val xxs = 4.dp
    val xs = 8.dp
    val sm = 12.dp
    val md = 16.dp
    val lg = 24.dp
    val xl = 32.dp
    val xxl = 48.dp
}

object AshCornerRadius {
    val sm = 8.dp
    val md = 12.dp
    val lg = 16.dp
    val xl = 20.dp
    val continuous = 22.dp
}

object AshColors {
    // Brand colors
    val ashAccent = Color(0xFF5856D6) // systemIndigo
    val ashDanger = Color(0xFFFF3B30) // systemRed
    val ashSuccess = Color(0xFF34C759) // systemGreen
    val ashWarning = Color(0xFFFF9500) // systemOrange/Amber

    // Conversation colors (matching iOS)
    val indigo = Color(0xFF5856D6)
    val blue = Color(0xFF007AFF)
    val purple = Color(0xFFAF52DE)
    val pink = Color(0xFFFF2D55)
    val red = Color(0xFFFF3B30)
    val orange = Color(0xFFFF9500)
    val yellow = Color(0xFFFFCC00)
    val green = Color(0xFF34C759)
    val mint = Color(0xFF00C7BE)
    val teal = Color(0xFF5AC8FA)
}

object AshTypography {
    val largeTitleSize = 34.sp
    val titleSize = 28.sp
    val title2Size = 22.sp
    val title3Size = 20.sp
    val headlineSize = 17.sp
    val bodySize = 17.sp
    val calloutSize = 16.sp
    val subheadSize = 15.sp
    val footnoteSize = 13.sp
    val captionSize = 12.sp
    val caption2Size = 11.sp
}

object AshSizes {
    val iconSmall = 16.dp
    val iconMedium = 24.dp
    val iconLarge = 32.dp
    val iconXLarge = 48.dp
    val iconXXLarge = 64.dp

    val buttonHeight = 50.dp
    val buttonMinWidth = 88.dp

    val cardMinHeight = 72.dp
    val qrCodeSize = 300.dp
}
