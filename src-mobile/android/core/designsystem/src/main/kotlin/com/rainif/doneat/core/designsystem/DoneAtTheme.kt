package com.rainif.doneat.core.designsystem

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.snap
import androidx.compose.material3.ColorScheme
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.Color
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
    val animatedScheme = animatedThemeColors(scheme, reduced)
    CompositionLocalProvider(
        LocalDoneAtStateColors provides DoneAtStateColors.from(animatedScheme, dark),
        LocalDoneAtMotion provides DoneAtMotion(reduced),
        LocalDoneAtRecordsColors provides if (dark) DoneAtRecordsColors.dark else DoneAtRecordsColors.light,
    ) {
        MaterialTheme(colorScheme = animatedScheme, shapes = DoneAtShapes.material, typography = DoneAtType.material, content = content)
    }
}

/** Settings → Accessibility → Remove animations sets the animator scale to 0. */
fun systemRemovesAnimations(context: Context) =
    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f

/** Retargets from the current colour when toggled again; no duplicate screens or state resets. */
@Composable
private fun animatedThemeColors(target: ColorScheme, reduced: Boolean): ColorScheme {
    @Composable
    fun color(value: Color): Color {
        val animated by animateColorAsState(value,
            animationSpec = if (reduced) snap() else DoneAtMotion(false).phase(), label = "themeColor")
        return animated
    }
    return target.copy(
        primary = color(target.primary),
        onPrimary = color(target.onPrimary),
        primaryContainer = color(target.primaryContainer),
        onPrimaryContainer = color(target.onPrimaryContainer),
        inversePrimary = color(target.inversePrimary),
        secondary = color(target.secondary),
        onSecondary = color(target.onSecondary),
        secondaryContainer = color(target.secondaryContainer),
        onSecondaryContainer = color(target.onSecondaryContainer),
        tertiary = color(target.tertiary),
        onTertiary = color(target.onTertiary),
        tertiaryContainer = color(target.tertiaryContainer),
        onTertiaryContainer = color(target.onTertiaryContainer),
        background = color(target.background),
        onBackground = color(target.onBackground),
        surface = color(target.surface),
        onSurface = color(target.onSurface),
        surfaceVariant = color(target.surfaceVariant),
        onSurfaceVariant = color(target.onSurfaceVariant),
        surfaceTint = color(target.surfaceTint),
        inverseSurface = color(target.inverseSurface),
        inverseOnSurface = color(target.inverseOnSurface),
        error = color(target.error),
        onError = color(target.onError),
        errorContainer = color(target.errorContainer),
        onErrorContainer = color(target.onErrorContainer),
        outline = color(target.outline),
        outlineVariant = color(target.outlineVariant),
        scrim = color(target.scrim),
        surfaceBright = color(target.surfaceBright),
        surfaceDim = color(target.surfaceDim),
        surfaceContainerLowest = color(target.surfaceContainerLowest),
        surfaceContainerLow = color(target.surfaceContainerLow),
        surfaceContainer = color(target.surfaceContainer),
        surfaceContainerHigh = color(target.surfaceContainerHigh),
        surfaceContainerHighest = color(target.surfaceContainerHighest),
    )
}
