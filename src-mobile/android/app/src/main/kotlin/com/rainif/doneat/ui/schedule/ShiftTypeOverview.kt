package com.rainif.doneat.ui.schedule

import android.content.res.Resources
import android.text.format.DateFormat
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.schedule.AnnualShiftDateRange
import com.rainif.doneat.core.domain.schedule.ExtendedSchedulePlan
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.l10n.Strings
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

internal data class ShiftDateCoverage(val first: String, val last: String, val count: Int)

internal fun estimatedCoverageYears(holidays: HolidayCalendar, region: String?, from: String): List<Int> {
    if (region.isNullOrEmpty()) return emptyList()
    val start = LocalDate.parse(from)
    val last = start.plusYears(1).minusDays(1)
    return (start.year..last.year).filter { holidays.isEstimated(it, region) }
}

/** Same next-calendar-year window and resolver as the iOS shift type overview. */
internal fun shiftDateCoverage(plan: ExtendedSchedulePlan, from: String): Map<UUID, ShiftDateCoverage> {
    val start = LocalDate.parse(from)
    val end = start.plusYears(1)
    val resolver = ExtendedScheduleResolver(plan)
    val result = mutableMapOf<UUID, ShiftDateCoverage>()
    var date = start
    while (date < end) {
        val id = resolver.day(date.toEpochDay().toInt()).shiftTypeID
        if (id != null) {
            val key = date.toString()
            val previous = result[id]
            result[id] = ShiftDateCoverage(previous?.first ?: key, key, (previous?.count ?: 0) + 1)
        }
        date = date.plusDays(1)
    }
    return result
}

internal fun coverageLabel(res: Resources, locale: Locale, coverage: ShiftDateCoverage?): String {
    if (coverage == null) return res.getString(R.string.extendedNoAssignedDates)
    val formatter = DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "yMMMd"), locale)
    return Strings.extendedAssignedDateBounds(res,
        formatter.format(LocalDate.parse(coverage.first)), formatter.format(LocalDate.parse(coverage.last)),
        java.text.NumberFormat.getIntegerInstance(locale).format(coverage.count))
}

internal fun annualRangeLabel(res: Resources, locale: Locale, range: AnnualShiftDateRange): String {
    val formatter = DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "MMMd"), locale)
    return Strings.extendedAnnualRangeLabel(res,
        formatter.format(LocalDate.of(2000, range.startMonth, range.startDay)),
        formatter.format(LocalDate.of(2000, range.endMonth, range.endDay)))
}
