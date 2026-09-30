package com.rainif.doneat.core.designsystem

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * DoneAt's colour tokens. The brand is the shared orange (iOS `OWCDesign.orange`);
 * surfaces match iOS grouped backgrounds, so the accent marks the current state and the
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
        background = Color(0xFFF2F2F7),
        onBackground = Color(0xFF000000),
        surface = Color(0xFFF2F2F7),
        onSurface = Color(0xFF000000),
        surfaceVariant = Color(0xFFE5E5EA),
        onSurfaceVariant = Color(0xFF5F5F66),
        surfaceTint = Color(0xFFC2410C),
        inverseSurface = Color(0xFF2C2C2E),
        inverseOnSurface = Color(0xFFF2F2F7),
        outline = Color(0xFF767680),
        outlineVariant = Color(0xFFC6C6C8),
        surfaceBright = Color(0xFFFFFFFF),
        surfaceDim = Color(0xFFE5E5EA),
        surfaceContainerLowest = Color(0xFFFFFFFF),
        surfaceContainerLow = Color(0xFFFFFFFF),
        surfaceContainer = Color(0xFFFFFFFF),
        surfaceContainerHigh = Color(0xFFFFFFFF),
        surfaceContainerHighest = Color(0xFFE5E5EA),
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
        background = Color(0xFF000000),
        onBackground = Color(0xFFF2F2F7),
        surface = Color(0xFF000000),
        onSurface = Color(0xFFF2F2F7),
        surfaceVariant = Color(0xFF2C2C2E),
        onSurfaceVariant = Color(0xFFAEAEB2),
        surfaceTint = Color(0xFFFF9A5C),
        inverseSurface = Color(0xFFF2F2F7),
        inverseOnSurface = Color(0xFF2C2C2E),
        outline = Color(0xFF8E8E93),
        outlineVariant = Color(0xFF38383A),
        surfaceBright = Color(0xFF3A3A3C),
        surfaceDim = Color(0xFF000000),
        surfaceContainerLowest = Color(0xFF000000),
        surfaceContainerLow = Color(0xFF1C1C1E),
        surfaceContainer = Color(0xFF1C1C1E),
        surfaceContainerHigh = Color(0xFF2C2C2E),
        surfaceContainerHighest = Color(0xFF3A3A3C),
    )

    /** Wallpaper colours supply accents, while page/card surfaces retain iOS's neutral hierarchy. */
    fun withNeutralSurfaces(scheme: ColorScheme, dark: Boolean): ColorScheme {
        val base = if (dark) this.dark else light
        return scheme.copy(
            background = base.background, onBackground = base.onBackground,
            surface = base.surface, onSurface = base.onSurface,
            surfaceVariant = base.surfaceVariant, onSurfaceVariant = base.onSurfaceVariant,
            inverseSurface = base.inverseSurface, inverseOnSurface = base.inverseOnSurface,
            outline = base.outline, outlineVariant = base.outlineVariant,
            surfaceBright = base.surfaceBright, surfaceDim = base.surfaceDim,
            surfaceContainerLowest = base.surfaceContainerLowest,
            surfaceContainerLow = base.surfaceContainerLow, surfaceContainer = base.surfaceContainer,
            surfaceContainerHigh = base.surfaceContainerHigh, surfaceContainerHighest = base.surfaceContainerHighest,
        )
    }

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
    /** The progress meter's fill in overtime: a deeper orange than `primary` (iOS `OWCDesign.orangeDeep`). */
    val overtimeMeter: Color,
    val onOvertimeMeter: Color,
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
            overtimeMeter = if (dark) Color(0xFFFF7A2E) else Color(0xFF9A3412),
            onOvertimeMeter = if (dark) Color(0xFF3A1400) else Color(0xFFFFFFFF),
        )
    }
}

val LocalDoneAtStateColors = staticCompositionLocalOf { DoneAtStateColors.from(DoneAtColors.light, dark = false) }
