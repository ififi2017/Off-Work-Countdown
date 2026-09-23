package com.rainif.doneat.core.designsystem

import android.content.Context
import android.os.Build
import android.provider.Settings
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext

/** Light, dark or the system's choice; independent of brand or dynamic colour (plan 01 §7.1). */
enum class ThemeMode { SYSTEM, LIGHT, DARK }

/** Wallpaper-based colour exists only on Android 12+; elsewhere the switch is not shown. */
val supportsDynamicColor get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

/**
 * The app theme. Brand colour by default; dynamic colour only when the user
 * turns it on and the platform supports it. Motion follows the system's
 * "remove animations" setting unless [reducedMotion] overrides it (the
 * design gallery's probe).
 */
@Composable
fun DoneAtTheme(
    themeMode: ThemeMode = ThemeMode.SYSTEM,
    dynamicColor: Boolean = false,
    reducedMotion: Boolean? = null,
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val dark = when (themeMode) {
        ThemeMode.SYSTEM -> isSystemInDarkTheme()
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }
    val scheme = when {
        dynamicColor && supportsDynamicColor -> if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        dark -> DoneAtColors.dark
        else -> DoneAtColors.light
    }
    val reduced = reducedMotion ?: remember(context) { systemRemovesAnimations(context) }
    CompositionLocalProvider(
        LocalDoneAtStateColors provides DoneAtStateColors.from(scheme, dark),
        LocalDoneAtMotion provides DoneAtMotion(reduced),
    ) {
        MaterialTheme(colorScheme = scheme, shapes = DoneAtShapes.material, typography = DoneAtType.material, content = content)
    }
}

/** Settings → Accessibility → Remove animations sets the animator scale to 0. */
fun systemRemovesAnimations(context: Context) =
    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
