package com.rainif.doneat.core.designsystem

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * DoneAt's colour tokens. The brand is the shared orange (iOS `OWCDesign.orange`);
 * surfaces are warm neutrals, so the orange marks the current state and the
 * main action rather than tinting the whole screen.
 *
 * Text and icon pairs meet WCAG AA (4.5:1) in both schemes; `DoneAtColorsTest`
 * holds every pair to it. The vivid brand orange fails that on light surfaces,
 * so light `primary` is a deeper tone of it and [DoneAtColors.brand] is kept for
 * decoration (the mark, a celebration), never for text or data.
 */
object DoneAtColors {
    /** iOS `OWCDesign.orange`: decoration only. */
    val brand = Color(0xFFF97316)

    val light: ColorScheme = lightColorScheme(
        primary = Color(0xFFC2410C),
        onPrimary = Color(0xFFFFFFFF),
        primaryContainer = Color(0xFFFFDBCC),
        onPrimaryContainer = Color(0xFF5A1C00),
        inversePrimary = Color(0xFFFFB690),
        secondary = Color(0xFF77574A),
        onSecondary = Color(0xFFFFFFFF),
        secondaryContainer = Color(0xFFF5DED4),
        onSecondaryContainer = Color(0xFF2C160C),
        tertiary = Color(0xFF3B6470),
        onTertiary = Color(0xFFFFFFFF),
        tertiaryContainer = Color(0xFFBFE9F7),
        onTertiaryContainer = Color(0xFF001F26),
        background = Color(0xFFFFF8F6),
        onBackground = Color(0xFF231A16),
        surface = Color(0xFFFFF8F6),
        onSurface = Color(0xFF231A16),
        surfaceVariant = Color(0xFFF4DED5),
        onSurfaceVariant = Color(0xFF53433C),
        surfaceTint = Color(0xFFC2410C),
        inverseSurface = Color(0xFF392E2A),
        inverseOnSurface = Color(0xFFFFEDE6),
        outline = Color(0xFF85736B),
        outlineVariant = Color(0xFFD8C2B9),
        surfaceBright = Color(0xFFFFF8F6),
        surfaceDim = Color(0xFFE8D6CF),
        surfaceContainerLowest = Color(0xFFFFFFFF),
        surfaceContainerLow = Color(0xFFFFF1EC),
        surfaceContainer = Color(0xFFFCEAE3),
        surfaceContainerHigh = Color(0xFFF6E5DE),
        surfaceContainerHighest = Color(0xFFF1DFD8),
    )

    val dark: ColorScheme = darkColorScheme(
        // iOS dark accent is #FF872E; this keeps its hue at a tone that carries dark text.
        primary = Color(0xFFFF9A5C),
        onPrimary = Color(0xFF3A1400),
        primaryContainer = Color(0xFF7A3000),
        onPrimaryContainer = Color(0xFFFFDBCB),
        inversePrimary = Color(0xFFC2410C),
        secondary = Color(0xFFE7BDAD),
        onSecondary = Color(0xFF442A1F),
        secondaryContainer = Color(0xFF5D4034),
        onSecondaryContainer = Color(0xFFFFDBCC),
        tertiary = Color(0xFFA3CDDB),
        onTertiary = Color(0xFF033540),
        tertiaryContainer = Color(0xFF214C57),
        onTertiaryContainer = Color(0xFFBFE9F7),
        background = Color(0xFF1A110E),
        onBackground = Color(0xFFF1DFD8),
        surface = Color(0xFF1A110E),
        onSurface = Color(0xFFF1DFD8),
        surfaceVariant = Color(0xFF53433C),
        onSurfaceVariant = Color(0xFFD8C2B9),
        surfaceTint = Color(0xFFFF9A5C),
        inverseSurface = Color(0xFFF1DFD8),
        inverseOnSurface = Color(0xFF392E2A),
        outline = Color(0xFFA08D85),
        outlineVariant = Color(0xFF53433C),
        surfaceBright = Color(0xFF42372F),
        surfaceDim = Color(0xFF1A110E),
        surfaceContainerLowest = Color(0xFF140C09),
        surfaceContainerLow = Color(0xFF231A16),
        surfaceContainer = Color(0xFF271E1A),
        surfaceContainerHigh = Color(0xFF322824),
        surfaceContainerHighest = Color(0xFF3D3230),
    )
}

/**
 * Colours for states Material has no role for. Each is paired with a label or
 * icon wherever it is used: a phase is never told apart by colour alone.
 */
@Immutable
data class DoneAtStateColors(
    val work: Color,
    val onWork: Color,
    val rest: Color,
    val onRest: Color,
    val offWork: Color,
    val onOffWork: Color,
    val overtime: Color,
    val onOvertime: Color,
) {
    companion object {
        fun from(scheme: ColorScheme, dark: Boolean) = DoneAtStateColors(
            work = scheme.primaryContainer,
            onWork = scheme.onPrimaryContainer,
            rest = scheme.tertiaryContainer,
            onRest = scheme.onTertiaryContainer,
            offWork = scheme.surfaceContainerHighest,
            onOffWork = scheme.onSurface,
            // Amber, apart from both the orange and the error red.
            overtime = if (dark) Color(0xFF5C4300) else Color(0xFFFFDEA6),
            onOvertime = if (dark) Color(0xFFFFDEA6) else Color(0xFF271900),
        )
    }
}

val LocalDoneAtStateColors = staticCompositionLocalOf { DoneAtStateColors.from(DoneAtColors.light, dark = false) }
