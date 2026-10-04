package com.rainif.doneat.core.designsystem

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Reports are a standalone story stage, matching iOS ReportPalette rather than app surfaces. */
object DoneAtReportPalette {
    val deep = Color(0xFF130A1B)
    val plum = Color(0xFF2B1935)
    val cream = Color(0xFFFFF1D8)
    val orange = Color(0xFFF97316)
    val energy = Color(0xFFB83F20)
    val warmField = Color(0xFF6B2938)
    val night = Color(0xFF292666)
    val calmField = Color(0xFF57479E)
    val hot = Color(0xFFFF4538)
    val moon = Color(0xFFB8ADFA)
    val restWarm = Color(0xFFF5D49C)
    val gold = Color(0xFFFFC24D)
    val ink = Color.White
    val muted = Color.White.copy(alpha = .65f)
    val track = Color.White.copy(alpha = .18f)
    val control = Color.White.copy(alpha = .12f)
}

object DoneAtReportLayout {
    val page = 22.dp
    val setupHero = 46.sp
    val readingHero = 34.sp
    val readingWeekArtHeight = 240.dp
    val readingMonthArtHeight = 300.dp
    val readingInset = 18.dp
    val readingRowVertical = 14.dp
    val storyHero = 72.sp
    val storyHeadline = 42.sp
    val teaserHeight = 270.dp
    val artHeight = 360.dp
    val readingCardRadius = 22.dp
    val unitSize = 23.sp
    val compactArtHeight = 220.dp
    val stageTop = 28.dp
    val controlSize = 48.dp
    val progressHeight = 3.dp
}

/** iOS ReportEase: deterministic chapter drawing, paused by the report's display clock. */
object DoneAtReportMotion {
    fun window(value: Float, from: Float, to: Float) = ((value - from) / (to - from).coerceAtLeast(.0001f)).coerceIn(0f, 1f)
    fun outCubic(value: Float): Float { val t = 1 - value.coerceIn(0f, 1f); return 1 - t * t * t }
    fun inOutCubic(value: Float): Float {
        val t = value.coerceIn(0f, 1f)
        return if (t < .5f) 4 * t * t * t else 1 - (-2 * t + 2).let { it * it * it } / 2
    }
    fun outBack(value: Float, overshoot: Float = 1.5f): Float {
        val t = value.coerceIn(0f, 1f) - 1
        return 1 + (overshoot + 1) * t * t * t + overshoot * t * t
    }
    fun stagger(value: Float, index: Int, count: Int, span: Float = .5f): Float =
        if (count <= 1) value.coerceIn(0f, 1f) else window(value, index.toFloat() / (count - 1) * (1 - span), index.toFloat() / (count - 1) * (1 - span) + span)
    val morphCurve = androidx.compose.animation.core.CubicBezierEasing(.42f, 0f, .58f, 1f)
    val calendar = 2_600L to 1_900L
    val weekCalendar = 2_000L to 1_900L
    val hours = 2_800L to 2_000L
    val overtime = 2_200L to 2_100L
    val baseline = 1_900L to 2_200L
    val rest = 2_400L to 2_100L
    val ahead = 2_200L to 2_300L
    val focus = 2_000L to 2_000L
    val income = 2_100L to 2_200L
    val summary = 1_400L to 0L
}
