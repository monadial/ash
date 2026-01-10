package com.monadial.ash.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

// ASH brand colors - Indigo theme
val AshIndigo = Color(0xFF5856D6)
val AshIndigoLight = Color(0xFF7A79E0)
val AshIndigoDark = Color(0xFF4240B0)

private val DarkColorScheme = darkColorScheme(
    primary = AshIndigo,
    onPrimary = Color.White,
    primaryContainer = AshIndigoDark,
    onPrimaryContainer = Color.White,
    secondary = AshIndigoLight,
    onSecondary = Color.White,
    background = Color(0xFF121212),
    surface = Color(0xFF1E1E1E),
    onBackground = Color.White,
    onSurface = Color.White,
    error = Color(0xFFFF453A),
    onError = Color.White,
)

private val LightColorScheme = lightColorScheme(
    primary = AshIndigo,
    onPrimary = Color.White,
    primaryContainer = AshIndigoLight,
    onPrimaryContainer = Color.White,
    secondary = AshIndigoDark,
    onSecondary = Color.White,
    background = Color(0xFFFFFBFE),
    surface = Color.White,
    onBackground = Color(0xFF1C1B1F),
    onSurface = Color(0xFF1C1B1F),
    error = Color(0xFFFF3B30),
    onError = Color.White,
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
        content = content
    )
}
