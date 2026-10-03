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
    val gold = Color(0xFFFFC24D)
    val ink = Color.White
    val muted = Color.White.copy(alpha = .65f)
    val track = Color.White.copy(alpha = .18f)
    val control = Color.White.copy(alpha = .12f)
}

object DoneAtReportLayout {
    val page = 22.dp
    val setupHero = 48.sp
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
