package com.monadial.ash.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp

/**
 * ASH Theme - Material Design 3 compliant color scheme
 *
 * Color roles follow M3 guidelines:
 * - primary: Brand color, high emphasis elements
 * - onPrimary: Content on primary (must have sufficient contrast)
 * - primaryContainer: Less prominent container using primary
 * - onPrimaryContainer: Content on primaryContainer (must contrast with primaryContainer)
 *
 * See: https://m3.material.io/styles/color/roles
 */

// ASH brand colors - Indigo theme
private val AshIndigo = Color(0xFF5856D6)
private val AshIndigoLight = Color(0xFFE8E7FF)  // Light container color
private val AshIndigoDark = Color(0xFF4240B0)

// Tertiary - Teal accent for visual interest
private val AshTeal = Color(0xFF00897B)
private val AshTealLight = Color(0xFFE0F2F1)
private val AshTealDark = Color(0xFF00695C)

// Error colors
private val AshError = Color(0xFFBA1A1A)
private val AshErrorLight = Color(0xFFFFDAD6)
private val AshOnErrorLight = Color(0xFF410002)

// Dark theme colors
private val AshErrorDark = Color(0xFFFFB4AB)
private val AshErrorContainerDark = Color(0xFF93000A)
private val AshOnErrorDark = Color(0xFF690005)

/**
 * Dark color scheme following Material 3 guidelines
 * Dark themes use lighter tones of colors
 */
private val DarkColorScheme = darkColorScheme(
    // Primary
    primary = Color(0xFFBFBDFF),  // Lighter primary for dark theme
    onPrimary = Color(0xFF2A2785),
    primaryContainer = Color(0xFF413E9C),
    onPrimaryContainer = Color(0xFFE2DFFF),

    // Secondary
    secondary = Color(0xFFC6C3DC),
    onSecondary = Color(0xFF2F2D42),
    secondaryContainer = Color(0xFF454359),
    onSecondaryContainer = Color(0xFFE3DFF9),

    // Tertiary
    tertiary = Color(0xFF80CBC4),
    onTertiary = Color(0xFF00382F),
    tertiaryContainer = Color(0xFF005046),
    onTertiaryContainer = Color(0xFFA1F0E7),

    // Error
    error = AshErrorDark,
    onError = AshOnErrorDark,
    errorContainer = AshErrorContainerDark,
    onErrorContainer = Color(0xFFFFDAD6),

    // Background & Surface
    background = Color(0xFF1C1B1F),
    onBackground = Color(0xFFE6E1E5),
    surface = Color(0xFF1C1B1F),
    onSurface = Color(0xFFE6E1E5),
    surfaceVariant = Color(0xFF49454F),
    onSurfaceVariant = Color(0xFFCAC4D0),

    // Outline
    outline = Color(0xFF938F99),
    outlineVariant = Color(0xFF49454F),

    // Inverse
    inverseSurface = Color(0xFFE6E1E5),
    inverseOnSurface = Color(0xFF313033),
    inversePrimary = AshIndigo,

    // Surface tint
    surfaceTint = Color(0xFFBFBDFF),
)

/**
 * Light color scheme following Material 3 guidelines
 * Always pair colors with their on- variants for proper contrast
 */
private val LightColorScheme = lightColorScheme(
    // Primary - main brand color
    primary = AshIndigo,
    onPrimary = Color.White,
    primaryContainer = AshIndigoLight,
    onPrimaryContainer = Color(0xFF1A1764),  // Dark text on light container

    // Secondary - less prominent than primary
    secondary = Color(0xFF605D71),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFE6E0F9),
    onSecondaryContainer = Color(0xFF1D1A2C),

    // Tertiary - accent color for visual interest
    tertiary = AshTeal,
    onTertiary = Color.White,
    tertiaryContainer = AshTealLight,
    onTertiaryContainer = AshTealDark,

    // Error
    error = AshError,
    onError = Color.White,
    errorContainer = AshErrorLight,
    onErrorContainer = AshOnErrorLight,

    // Background & Surface
    background = Color(0xFFFFFBFE),
    onBackground = Color(0xFF1C1B1F),
    surface = Color(0xFFFFFBFE),
    onSurface = Color(0xFF1C1B1F),
    surfaceVariant = Color(0xFFE7E0EC),
    onSurfaceVariant = Color(0xFF49454F),

    // Outline - for borders and dividers
    outline = Color(0xFF79747E),
    outlineVariant = Color(0xFFCAC4D0),

    // Inverse - for snackbars, tooltips
    inverseSurface = Color(0xFF313033),
    inverseOnSurface = Color(0xFFF4EFF4),
    inversePrimary = Color(0xFFBFBDFF),

    // Surface tint - used for tonal elevation
    surfaceTint = AshIndigo,
)

/**
 * Material 3 Typography scale
 * See: https://m3.material.io/styles/typography/type-scale-tokens
 */
private val AshTypography = Typography(
    // Display styles - large, expressive headlines
    displayLarge = TextStyle(
        fontSize = 57.sp,
        lineHeight = 64.sp,
        fontWeight = FontWeight.Normal,
        letterSpacing = (-0.25).sp
    ),
    displayMedium = TextStyle(
        fontSize = 45.sp,
        lineHeight = 52.sp,
        fontWeight = FontWeight.Normal,
        letterSpacing = 0.sp
    ),
    displaySmall = TextStyle(
        fontSize = 36.sp,
        lineHeight = 44.sp,
        fontWeight = FontWeight.Normal,
        letterSpacing = 0.sp
    ),

    // Headline styles - section headers
    headlineLarge = TextStyle(
        fontSize = 32.sp,
        lineHeight = 40.sp,
        fontWeight = FontWeight.Normal,
        letterSpacing = 0.sp
    ),
    headlineMedium = TextStyle(
        fontSize = 28.sp,
        lineHeight = 36.sp,
        fontWeight = FontWeight.Normal,
        letterSpacing = 0.sp
    ),
    headlineSmall = TextStyle(
        fontSize = 24.sp,
        lineHeight = 32.sp,
        fontWeight = FontWeight.Normal,
        letterSpacing = 0.sp
    ),

    // Title styles - cards, dialogs, app bars
    titleLarge = TextStyle(
        fontSize = 22.sp,
        lineHeight = 28.sp,
        fontWeight = FontWeight.Medium,
        letterSpacing = 0.sp
    ),
    titleMedium = TextStyle(
        fontSize = 16.sp,
        lineHeight = 24.sp,
        fontWeight = FontWeight.Medium,
        letterSpacing = 0.15.sp
    ),
    titleSmall = TextStyle(
        fontSize = 14.sp,
        lineHeight = 20.sp,
        fontWeight = FontWeight.Medium,
        letterSpacing = 0.1.sp
    ),

    // Body styles - main content text
    bodyLarge = TextStyle(
        fontSize = 16.sp,
        lineHeight = 24.sp,
        fontWeight = FontWeight.Normal,
        letterSpacing = 0.5.sp
    ),
    bodyMedium = TextStyle(
        fontSize = 14.sp,
        lineHeight = 20.sp,
        fontWeight = FontWeight.Normal,
        letterSpacing = 0.25.sp
    ),
    bodySmall = TextStyle(
        fontSize = 12.sp,
        lineHeight = 16.sp,
        fontWeight = FontWeight.Normal,
        letterSpacing = 0.4.sp
    ),

    // Label styles - buttons, chips, badges
    labelLarge = TextStyle(
        fontSize = 14.sp,
        lineHeight = 20.sp,
        fontWeight = FontWeight.Medium,
        letterSpacing = 0.1.sp
    ),
    labelMedium = TextStyle(
        fontSize = 12.sp,
        lineHeight = 16.sp,
        fontWeight = FontWeight.Medium,
        letterSpacing = 0.5.sp
    ),
    labelSmall = TextStyle(
        fontSize = 11.sp,
        lineHeight = 16.sp,
        fontWeight = FontWeight.Medium,
        letterSpacing = 0.5.sp
    )
)

/**
 * Material 3 Shape scale
 * See: https://m3.material.io/styles/shape/shape-scale-tokens
 */
private val AshShapes = Shapes(
    extraSmall = RoundedCornerShape(4.dp),   // Small interactive elements
    small = RoundedCornerShape(8.dp),        // Chips, small buttons
    medium = RoundedCornerShape(12.dp),      // Cards, dialogs
    large = RoundedCornerShape(16.dp),       // FAB, large surfaces
    extraLarge = RoundedCornerShape(28.dp)   // Bottom sheets, full-height containers
)

@Composable
fun AshTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false, // Disabled to maintain brand consistency
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = AshTypography,
        shapes = AshShapes,
        content = content
    )
}
