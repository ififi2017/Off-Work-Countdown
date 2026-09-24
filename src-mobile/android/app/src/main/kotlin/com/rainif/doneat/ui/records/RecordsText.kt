package com.rainif.doneat.ui.records

import android.content.res.Resources
import android.icu.text.MeasureFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import android.text.format.DateFormat
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.records.RecordsDayAppearance
import com.rainif.doneat.core.domain.records.RecordsDayCell
import com.rainif.doneat.core.domain.records.RecordsDaySource
import com.rainif.doneat.core.domain.records.TimeAllocationKind
import com.rainif.doneat.ui.timer.TimerText
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * The records pages' formatters (iOS `RecordsQueries` date helpers and
 * `AppText`). Dates are read in the records time zone, never the device's, so
 * travelling never moves a record to another day; the language is the app's.
 */
class RecordsText(
    private val res: Resources,
    val locale: Locale,
    val zone: ZoneId,
    use24Hour: Boolean,
    private val timer: TimerText,
) {
    private fun pattern(skeleton: String) = DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, skeleton), locale)

    private val dayTitle = pattern("EEEMMMd")
    private val monthDay = pattern("MMMd")
    private val weekdayNarrow = pattern("EEEEE")
    private val monthYear = pattern("LLLLy")
    private val month = pattern("LLLL")
    private val time = pattern(if (use24Hour) "Hm" else "hm")

    fun string(id: Int) = res.getString(id)

    /** "Wed, 26 Aug": a day's identity in a list. */
    fun dayTitle(day: LocalDate): String = dayTitle.format(day)
    fun dayTitle(dayKey: String): String = runCatching { dayTitle(LocalDate.parse(dayKey)) }.getOrDefault(dayKey)

    fun monthDay(day: LocalDate): String = monthDay.format(day)
    fun weekdayNarrow(day: LocalDate): String = weekdayNarrow.format(day)
    fun monthYear(day: LocalDate): String = monthYear.format(day)
    /** "August": a compact month control where the year is already visible. */
    fun month(day: LocalDate): String = month.format(day)

    /** A clock time as read in the records zone. */
    fun time(atMs: Double): String = time.format(Instant.ofEpochMilli(atMs.toLong()).atZone(zone))

    /** A wall-clock reading, as a picker shows it. */
    fun clock(value: java.time.LocalTime): String = time.format(value)

    /** Each end isolated, so an AM/PM marker stays with its own digits in either direction. */
    fun timeRange(startMs: Double, endMs: Double) = "${TimerText.isolate(time(startMs))} – ${TimerText.isolate(time(endMs))}"

    fun count(value: Int): String = NumberFormat.getIntegerInstance(locale).format(value)

    /** "8 h 30 m"; hours and minutes only. */
    fun duration(ms: Double): String = timer.relativeDuration(ms)

    /** As [duration], with days once a total passes 24 hours: week and month sums get long. */
    fun recordsDuration(ms: Double): String {
        val total = maxOf(0L, (ms / 1_000).toLong())
        if (total < 86_400) return duration(ms)
        val measures = buildList {
            add(Measure(total / 86_400, MeasureUnit.DAY))
            (total % 86_400 / 3_600).takeIf { it > 0 }?.let { add(Measure(it, MeasureUnit.HOUR)) }
            (total % 3_600 / 60).takeIf { it > 0 }?.let { add(Measure(it, MeasureUnit.MINUTE)) }
        }
        return MeasureFormat.getInstance(locale, MeasureFormat.FormatWidth.NARROW).formatMeasures(*measures.toTypedArray())
    }

    fun percent(value: Double, fractionDigits: Int = 1): String = NumberFormat.getPercentInstance(locale).apply {
        minimumFractionDigits = fractionDigits
        maximumFractionDigits = fractionDigits
    }.format(value / 100)

    /** Every amount goes through the one mask. */
    fun money(value: Double?): String = timer.money(value)

    fun kindTitle(kind: TimeAllocationKind): String = res.getString(
        when (kind) {
            TimeAllocationKind.WORK -> R.string.recordsWorkRegular
            TimeAllocationKind.OVERTIME -> R.string.recordsOvertime
            TimeAllocationKind.WORK_BREAK -> R.string.recordsBreakTime
            TimeAllocationKind.SLEEP -> R.string.recordsSleep
            TimeAllocationKind.FREE -> R.string.recordsFreeAwakeShort
            TimeAllocationKind.UNCLASSIFIED -> R.string.recordsUnclassified
        },
    )

    fun sourceTitle(source: RecordsDaySource, sleepFromHealth: Boolean = false): String = res.getString(
        when (source) {
            RecordsDaySource.RECORDED -> R.string.recordsSourceRecorded
            RecordsDaySource.SCHEDULED, RecordsDaySource.SCHEDULE_ESTIMATE -> R.string.recordsSourceSchedule
            RecordsDaySource.CORRECTED -> R.string.recordsSourceOverride
            RecordsDaySource.EXCEPTION -> R.string.recordsSourceException
            RecordsDaySource.AFTER_NOW -> R.string.recordsSourceAfterNow
            RecordsDaySource.LIFE_PROJECTION -> R.string.recordsSourceProjection
            RecordsDaySource.PLANNED -> R.string.recordsPlanned
            RecordsDaySource.SLEEP_ESTIMATE -> if (sleepFromHealth) R.string.recordsSleepFromHealth else R.string.recordsSleepEstimated
            RecordsDaySource.UNRECORDED -> R.string.recordsUnrecorded
            RecordsDaySource.REST -> R.string.recordsRestDay
            RecordsDaySource.LOCKED -> R.string.recordsLockedDay
        },
    )

    /** One vocabulary for a cell's source (iOS `RecordsDayMarks.sourceKey`). */
    fun cellSource(cell: RecordsDayCell): String = res.getString(
        when {
            cell.appearance == RecordsDayAppearance.LOCKED -> R.string.recordsLockedDay
            cell.isProjection -> R.string.recordsSourceProjection
            else -> when (cell.appearance) {
                RecordsDayAppearance.UNRECORDED -> R.string.recordsUnrecorded
                RecordsDayAppearance.RECORDED -> if (cell.isFromSavedSchedule) R.string.recordsSourceSchedule else R.string.recordsSourceRecorded
                RecordsDayAppearance.CORRECTED -> R.string.recordsSourceOverride
                RecordsDayAppearance.PLANNED -> R.string.recordsPlanned
                RecordsDayAppearance.REST -> R.string.recordsRestDay
                RecordsDayAppearance.LOCKED -> R.string.recordsLockedDay
            }
        },
    )

    /** A locked day says only that it is locked: no date, no hours, nothing to read out from behind it. */
    fun cellDescription(cell: RecordsDayCell): String {
        if (cell.appearance == RecordsDayAppearance.LOCKED) return res.getString(R.string.recordsLockedDay)
        val parts = mutableListOf(dayTitle(cell.date), cellSource(cell))
        if (cell.workMs > 0) parts += recordsDuration(cell.workMs.toDouble())
        if (cell.overtimeMs > 0) parts += "${res.getString(R.string.recordsOvertime)} ${recordsDuration(cell.overtimeMs.toDouble())}"
        return parts.joinToString(", ")
    }
}
