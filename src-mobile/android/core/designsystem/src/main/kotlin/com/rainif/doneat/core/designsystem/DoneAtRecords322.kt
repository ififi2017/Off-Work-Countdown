package com.rainif.doneat.core.designsystem

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Scoped to the 3.2.2 Records presentation; existing consumers keep their tokens. */
object DoneAtRecords322 {
    val holidayLight = Color(0xFF248A3D)
    val holidayDark = Color(0xFF30D158)
    val dateSize = 32.dp
    /**
     * iOS `RecordsMonthCalendar`: a 60 pt row (3 pt top, 32 pt date, 13 pt gap holding a 12 pt
     * holiday strip in 9 pt type, 8 pt bar slot). In sp so the row grows with the capped text size,
     * as iOS's `@ScaledMetric` does, and the holiday name is never clipped.
     */
    val monthRowHeight = 60.sp
    val monthDateBarGap = 13.sp
    val monthHolidayHeight = 12.sp
    val monthHolidayText = 9.sp
    val monthBarSlot = 8.dp
    val holidayHeight = 18.dp
    val workBarHeight = 4.dp
    val weekHeight = 148.dp
    val weekBarWidth = 16.dp
    val yearDot = 6.dp
    val lifeYearHeight = 18.dp
    val outline = 1.25.dp
    val selectedOutline = 2.dp
    val allocationHeight = 230.dp
    val allocationWidth = 76.dp
}
