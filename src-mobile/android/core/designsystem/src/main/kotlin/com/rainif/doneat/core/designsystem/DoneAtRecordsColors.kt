package com.rainif.doneat.core.designsystem

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * The six time categories every records surface draws (iOS `OWCDesign.records*`,
 * which are system colours). The same hues on both platforms keep a shared
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
) {
    companion object {
        val light = DoneAtRecordsColors(
            work = Color(0xFF5856D6),
            overtime = Color(0xFFFF9500),
            workBreak = Color(0xFF30B0C7),
            sleep = Color(0xFF007AFF),
            free = Color(0xFFAF52DE),
            unclassified = Color(0xFFAEAEB2),
        )
        val dark = DoneAtRecordsColors(
            work = Color(0xFF5E5CE6),
            overtime = Color(0xFFFF9F0A),
            workBreak = Color(0xFF40C8E0),
            sleep = Color(0xFF0A84FF),
            free = Color(0xFFBF5AF2),
            unclassified = Color(0xFF636366),
        )
    }
}

val LocalDoneAtRecordsColors = staticCompositionLocalOf { DoneAtRecordsColors.light }
