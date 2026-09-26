package com.rainif.doneat.core.domain.reminders

import com.rainif.doneat.core.domain.records.DayResolution
import com.rainif.doneat.core.domain.records.FoundationCompat
import com.rainif.doneat.core.domain.records.RecordHistory
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.records.RecordsQueries
import com.rainif.doneat.core.domain.records.WorkObservation
import com.rainif.doneat.core.domain.records.WorkObservationKind
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.ShiftSnapshot
import com.rainif.doneat.core.domain.session.ShiftSession
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.LocalDate
import java.time.Instant

data class ScheduleCycleDay(val dayKey: String, val isWorkday: Boolean, val workMs: Long, val overtimeMs: Long, val isComplete: Boolean = true)

data class ScheduleCycleSummary(val workdayCount: Int, val workMs: Long, val overtimeMs: Long)

/**
 * The cycle-end summary (iOS `ScheduleCycleSummaryCalculator`): a cycle is the
 * contiguous run of resolved workdays immediately before a resolved rest day.
 * Exceptions and day edits have already won before the days reach it, and a
 * following day that did not resolve is never read as rest.
 */
object ScheduleCycleSummaryCalculator {
    /** iOS cycleEndSummaryNotificationBody's projection, before localization. */
    fun forShift(state: RecordState, session: ShiftSession, shift: ShiftSnapshot, authorized: Boolean): ScheduleCycleSummary? {
        val prefs = session.env.preferences
        if (!authorized || !prefs.cycleEndSummaryNotificationEnabled || prefs.scheduleMode == "off" ||
            !(shift.isWorkday || session.isForcedWorkday(shift))) return null
        val zone = FoundationCompat.javaZone(prefs.recordsTimeZoneIdentifier)
        val anchor = Instant.ofEpochMilli(shift.startAtMs.toLong()).atZone(zone).toLocalDate()
        val queries = RecordsQueries(state, session.env.holidays, zone, authorized = true)
        val days = queries.resolvedDays(anchor.minusDays(31), anchor.plusDays(1)).map { day ->
            ScheduleCycleDay(day.dayKey, day.isScheduledWorkday, day.segments.sumOf(::roundedLength),
                queries.overtimeSegments(day).sumOf(::roundedLength), !day.expansionFailed)
        }
        return summary(FoundationCompat.dayKey(anchor), days)
    }

    fun summary(endingAt: String, days: List<ScheduleCycleDay>): ScheduleCycleSummary? {
        val end = days.indexOfFirst { it.dayKey == endingAt }
        if (end < 0 || end + 1 >= days.size || !days[end].isWorkday) return null
        val following = days[end + 1]
        if (!following.isComplete || following.isWorkday) return null
        var start = end
        while (start > 0 && days[start - 1].isWorkday) start--
        val cycle = days.subList(start, end + 1)
        if (!cycle.all { it.isComplete }) return null
        return ScheduleCycleSummary(cycle.size, cycle.sumOf { it.workMs }, cycle.sumOf { it.overtimeMs })
    }

    /**
     * The 31 days before [anchorDayKey] through the day after, resolved from
     * the archive, as iOS feeds the calculator. A day whose schedule did not
     * expand is incomplete, so it can neither end nor join a cycle.
     */
    fun days(state: RecordState, anchorDayKey: String, holidays: HolidayCalendar): List<ScheduleCycleDay> {
        val anchor = LocalDate.parse(anchorDayKey)
        val overtime = state.observations.filter { it.kind == WorkObservationKind.OVERTIME_DECLARED }.groupBy { it.shiftAnchorDate }
        return (-31L..1L).map { offset ->
            val day = RecordHistory.resolveDay(state, FoundationCompat.dayKey(anchor.plusDays(offset)), holidays)
            ScheduleCycleDay(
                dayKey = day.dayKey,
                isWorkday = day.isScheduledWorkday,
                workMs = day.segments.sumOf(::roundedLength),
                overtimeMs = overtimeSegments(day, overtime[day.dayKey].orEmpty()).sumOf(::roundedLength),
                isComplete = !day.expansionFailed,
            )
        }
    }

    private fun roundedLength(s: ShiftSegment) = FoundationCompat.roundedHalfAwayFromZero(maxOf(0.0, s.endAtMs - s.startAtMs)).toLong()

    /** The latest overtime declaration's stretch after the day's regular work (iOS `RecordsQueries.overtimeSegments`). */
    fun overtimeSegments(day: DayResolution, observations: List<WorkObservation>): List<ShiftSegment> {
        val latest = observations.filter { it.kind == WorkObservationKind.OVERTIME_DECLARED }
            .maxWithOrNull(compareBy<WorkObservation> { it.occurredAtMs }.thenBy { it.eventID })
            ?: return emptyList()
        return listOfNotNull(declaredOvertimeSegment(latest, day, avoidingRegularWork = true))
    }

    /** iOS `RecordsMetrics.declaredOvertimeSegment`. */
    fun declaredOvertimeSegment(observation: WorkObservation, day: DayResolution, avoidingRegularWork: Boolean): ShiftSegment? {
        if (observation.kind != WorkObservationKind.OVERTIME_DECLARED) return null
        val payload = observation.valueData?.let {
            FoundationCompat.base64(it)?.let { bytes -> runCatching { Json.parseToJsonElement(String(bytes)).jsonObject }.getOrNull() }
        } ?: return null
        val overtimeEnd = payload["overtimeEndAtMs"]?.jsonPrimitive?.doubleOrNull ?: return null
        var start = payload["plannedEndAtMs"]?.jsonPrimitive?.doubleOrNull
            ?: day.baseScheduleSegments.maxOfOrNull { it.endAtMs }
            ?: return null
        if (avoidingRegularWork) day.segments.maxOfOrNull { it.endAtMs }?.let { start = maxOf(start, it) }
        if (!start.isFinite() || !overtimeEnd.isFinite() || overtimeEnd <= start) return null
        return ShiftSegment(start, overtimeEnd)
    }
}
