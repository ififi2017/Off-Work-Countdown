package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.CountedOvertime
import com.rainif.doneat.core.domain.schedule.OvertimePay
import com.rainif.doneat.core.domain.session.SessionCommands
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

/**
 * Plan 024 phase 4: one past day's overtime as the Records day editor shows and
 * saves it (iOS `RecordOvertimeState`). A save writes a new `overtimeDeclared`
 * observation (the latest one counts); earlier observations are never changed.
 */
data class RecordOvertimeState(
    /** Whether the day already has an overtime declaration. */
    val hasDeclaration: Boolean,
    val startAtMs: Double,
    val endAtMs: Double,
    /** The hours that count, when they differ from the period; null counts the period. */
    val countedMs: Double?,
    /** 0 is unpaid overtime; see [OvertimePay]. */
    val payMultiplier: Double,
    /** Where the day's regular work ends: overtime before it is not overtime. */
    val regularEndAtMs: Double?,
    /** The planned clock-off the declaration is recorded against. */
    val plannedEndAtMs: Double?,
) {
    /** The period's length outside regular work, which is what Records measures. */
    val measuredMs: Double get() = max(0.0, endAtMs - max(startAtMs, regularEndAtMs ?: startAtMs))

    /** What statistics and pay use. */
    val effectiveCountedMs: Double get() = countedMs ?: measuredMs

    val isValid: Boolean get() = startAtMs.isFinite() && endAtMs.isFinite() && endAtMs > startAtMs

    /** One 15-minute step from the counted hours, from the nearest step. */
    fun steppedCountedMs(direction: Int): Double {
        val current = (effectiveCountedMs / COUNTED_STEP_MS).roundToLong() * COUNTED_STEP_MS
        return min(CountedOvertime.MAXIMUM_MS, max(0.0, current + direction * COUNTED_STEP_MS))
    }

    /** Moves the start to [minutes] past midnight on the day the period starts, keeping the end's clock time after it. */
    fun withStart(minutes: Int, zone: ZoneId): RecordOvertimeState {
        val day = localDate(startAtMs, zone)
        val start = atMinutes(day, minutes, zone)
        val endMinutes = minutesOf(endAtMs, zone)
        return copy(startAtMs = start).withEnd(endMinutes, zone)
    }

    /** Moves the end to [minutes] past midnight: the first such time after the start, so an end past midnight stays one period. */
    fun withEnd(minutes: Int, zone: ZoneId): RecordOvertimeState {
        val day = localDate(startAtMs, zone)
        var end = atMinutes(day, minutes, zone)
        if (end <= startAtMs) end = atMinutes(day.plusDays(1), minutes, zone)
        return copy(endAtMs = end)
    }

    /** The declaration observation's payload, as JSON. */
    val payload: String
        get() = SessionCommands.overtimePayload(
            overtimeEndAtMs = endAtMs,
            plannedEndAtMs = plannedEndAtMs,
            payMultiplier = payMultiplier.takeIf { it != 1.0 },
            overtimeStartAtMs = startAtMs,
            countedMs = countedMs,
        )

    /** Whether a save may write this state: a real period, a valid multiplier and counted hours. */
    val isSavable: Boolean
        get() = isValid && OvertimePay.normalized(payMultiplier) == payMultiplier &&
            (countedMs == null || CountedOvertime.normalized(countedMs) != null)

    companion object {
        const val COUNTED_STEP_MS = 15.0 * 60_000

        /**
         * The day's overtime as the records show it now, or a one-hour starting
         * point after the regular work for a day with none, paid at [defaultMultiplier].
         */
        fun load(dayKey: String, queries: RecordsQueries, defaultMultiplier: Double): RecordOvertimeState {
            val day = LocalDate.parse(dayKey)
            val resolution = queries.resolvedDays(day, day).firstOrNull()
            val regularEnd = resolution?.segments?.maxOfOrNull { it.endAtMs }
            val plannedEnd = resolution?.baseScheduleSegments?.maxOfOrNull { it.endAtMs }
            val segment = resolution?.let { queries.overtimeSegments(it).firstOrNull() }
            if (resolution != null && segment != null) {
                return RecordOvertimeState(
                    hasDeclaration = true,
                    startAtMs = segment.startAtMs,
                    endAtMs = segment.endAtMs,
                    countedMs = queries.overtimeCountedMs(resolution),
                    payMultiplier = queries.overtimePayMultiplier(resolution),
                    regularEndAtMs = regularEnd,
                    plannedEndAtMs = plannedEnd,
                )
            }
            val dayStart = day.atStartOfDay(queries.zone).toInstant().toEpochMilli().toDouble()
            val start = regularEnd ?: plannedEnd ?: (dayStart + 18 * 3_600_000)
            return RecordOvertimeState(
                hasDeclaration = false,
                startAtMs = start,
                endAtMs = start + 3_600_000,
                countedMs = null,
                payMultiplier = OvertimePay.normalized(defaultMultiplier),
                regularEndAtMs = regularEnd,
                plannedEndAtMs = plannedEnd,
            )
        }

        fun minutesOf(atMs: Double, zone: ZoneId): Int {
            val t = Instant.ofEpochMilli(atMs.toLong()).atZone(zone)
            return t.hour * 60 + t.minute
        }

        private fun localDate(atMs: Double, zone: ZoneId) = Instant.ofEpochMilli(atMs.toLong()).atZone(zone).toLocalDate()

        private fun atMinutes(day: LocalDate, minutes: Int, zone: ZoneId): Double =
            day.atTime(minutes / 60, minutes % 60).atZone(zone).toInstant().toEpochMilli().toDouble()
    }
}
