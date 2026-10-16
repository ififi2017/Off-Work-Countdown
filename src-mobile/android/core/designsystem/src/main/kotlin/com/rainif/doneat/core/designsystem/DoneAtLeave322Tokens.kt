package com.rainif.doneat.core.designsystem

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/** Scoped Time off 3.2.2 semantics; does not change existing Records or preview tokens. */
object DoneAtLeave322Tokens {
    val restLight = Color(0xFF34C759)
    val restDark = Color(0xFF30D158)
    /** Text retains the rest hue with readable contrast on the light white/grey surfaces. */
    val restTextLight = Color(0xFF176F2F)
    val restTextDark = restDark
    val barHeight = 8.dp
    val stripMaximumCell = 22.dp
    val stripGap = 2.dp
    val stripCorner = 2.5.dp
    val bandCorner = 4.dp
    val bandMinimumHeight = 16.dp
    val calendarDayMinimum = 66.dp
    val bridgeMiddleWidth = 56.dp
    val bridgeStackWidth = 320.dp
    const val bridgeStackFontScale = 1.5f
    const val usedAlpha = .55f
    val restBandAlpha = .14f
    val weekendAlpha = .38f
}
