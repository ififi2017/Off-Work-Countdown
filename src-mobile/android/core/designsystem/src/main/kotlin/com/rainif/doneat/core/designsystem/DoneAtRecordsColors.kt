package com.rainif.doneat.core.designsystem

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * The six time categories every records surface draws (iOS 3.2.2 `OWCDesign.records*`:
 * indigo work, translucent indigo breaks, grey sleep, green own time), and the Life stages
 * (warm childhood, cyan school, the same indigo work, green after retirement). The same hues on both platforms keep a shared
 * backup reading the same way; each has a dark variant for contrast.
 */
@Immutable
data class DoneAtRecordsColors(
    val work: Color,
    val overtime: Color,
    val workBreak: Color,
    val sleep: Color,
    val free: Color,
    val unclassified: Color,
    /** Life stages (iOS `OWCDesign.life*`). */
    val childhood: Color,
    val study: Color,
    val lifeWork: Color,
    val retirement: Color,
    val lifeUnset: Color,
) {
    companion object {
        val light = DoneAtRecordsColors(
            work = Color(0xFF5856D6),
            overtime = Color(0xFFFF9500),
            workBreak = Color(0x615856D6),
            sleep = Color(0xFFD1D1D6),
            free = Color(0xFF34C759),
            unclassified = Color(0xFFAEAEB2),
            childhood = Color(0xFFE8A33D),
            study = Color(0xFF30B0C7),
            lifeWork = Color(0xFF5856D6),
            retirement = Color(0xFF34C759),
            lifeUnset = Color(0x1F767680),
        )
        val dark = DoneAtRecordsColors(
            work = Color(0xFF5E5CE6),
            overtime = Color(0xFFFF9F0A),
            workBreak = Color(0x735E5CE6),
            sleep = Color(0xFF47474A),
            free = Color(0xFF30D158),
            unclassified = Color(0xFF636366),
            childhood = Color(0xFFF5BA4F),
            study = Color(0xFF40C7E0),
            lifeWork = Color(0xFF5E5CE6),
            retirement = Color(0xFF30D158),
            lifeUnset = Color(0x3D767680),
        )
    }
}

val LocalDoneAtRecordsColors = staticCompositionLocalOf { DoneAtRecordsColors.light }

object DoneAtRecordsStyle {
    const val estimateStrokeOpacity = .55f
    /** iOS secondary tint (~60%) with the month grid's additional 55% opacity. */
    const val calendarEstimateTintOpacity = .33f
}
