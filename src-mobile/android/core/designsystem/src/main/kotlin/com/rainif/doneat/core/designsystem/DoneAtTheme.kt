package com.rainif.doneat.core.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Placeholder brand accent; T04 replaces this with the full DoneAt token set (D-12).
private val DoneAtOrange = Color(0xFFFF8A00)

@Composable
fun DoneAtTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val colors = if (darkTheme) {
        darkColorScheme(primary = DoneAtOrange)
    } else {
        lightColorScheme(primary = DoneAtOrange)
    }
    MaterialTheme(colorScheme = colors, content = content)
}
