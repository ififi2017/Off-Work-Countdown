package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleContent
import com.rainif.doneat.core.domain.schedule.ExtendedSchedulePlan
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.ScheduleHours
import com.rainif.doneat.core.domain.schedule.ScheduleRules
import com.rainif.doneat.core.domain.schedule.WallClock

/**
 * Planned history from the archive. [expandableHours] is the only way to turn
 * a stored snapshot into runnable hours: decoding `configurationData` directly
 * silently loses the roster overlay (iOS `RecordCoordinator.expandableHours`).
 */
object RecordHistory {
    /**
     * A snapshot's hours with the roster laid over them:
     * - an extended snapshot keeps its saved types and rule over today's
     *   hand-set days (plus types created since, so newer days still resolve);
     * - a fixed snapshot takes frozen historical assignments, and legacy rows
     *   too when it predates the first extended snapshot.
     * Null when the stored hours do not decode or name a mode the rules lack.
     */
    fun expandableHours(state: RecordState, snapshot: ScheduleSnapshot, holidays: HolidayCalendar): ScheduleHours? {
        val stored = ScheduleHoursCodec.decodeBase64(snapshot.configurationData) ?: return null
        val hours = stored.scheduleHours() ?: return null
        val content = stored.extendedContent
        val plan = if (content != null) {
            contentPlan(state, content, holidays)
        } else {
            val includesLegacy = extendedScheduleStart(state)?.let { snapshot.effectiveFrom < it } ?: false
            ExtendedSchedulePlan.historical(state.rosterDays, state.extendedSchedule?.content?.shiftTypes.orEmpty(), includesLegacy)
        }
        return hours.copy(extended = plan)
    }

    /** The first day any snapshot followed an extended schedule. */
    fun extendedScheduleStart(state: RecordState): String? = state.snapshots
        .filter { ScheduleHoursCodec.decodeBase64(it.configurationData)?.extendedContent != null }
        .minOfOrNull { it.effectiveFrom }

    private fun contentPlan(state: RecordState, content: ExtendedScheduleContent, holidays: HolidayCalendar): ExtendedSchedulePlan {
        val saved = content.shiftTypes.map { it.id }.toSet()
        val liveTypes = state.extendedSchedule?.content?.shiftTypes.orEmpty()
        return ExtendedSchedulePlan(
            shiftTypes = content.shiftTypes + liveTypes.filter { it.id !in saved },
            rule = content.rule,
            handSetDays = ExtendedSchedulePlan.handSetDays(state.rosterDays),
            holidayRegionIdentifier = content.holidayRegionIdentifier,
            clearedFromDayKey = content.clearedFromDayKey,
            frozenShiftTypes = ExtendedSchedulePlan.frozenShiftTypes(state.rosterDays),
            holidays = holidays,
        )
    }

    /** One civil day of a snapshot, expanded in its period's zone. */
    fun expansion(state: RecordState, snapshot: ScheduleSnapshot, period: CareerPeriod, dayKey: String, holidays: HolidayCalendar): ScheduleExpansion {
        val hours = expandableHours(state, snapshot, holidays) ?: return ScheduleExpansion.FAILED
        val zone = FoundationCompat.javaZone(period.timeZoneIdentifier)
        val dayNumber = ExtendedScheduleResolver.dayNumber(dayKey) ?: return ScheduleExpansion.FAILED
        val midnight = CivilZone(zone).utcMs(dayNumber, WallClock.MIDNIGHT)
        val day = ScheduleRules.expandScheduleRange(hours, midnight, midnight, zone).firstOrNull() ?: return ScheduleExpansion.FAILED
        return ScheduleExpansion(day.isWorkday, day.segments)
    }

    /** A day's conclusion through the three-layer chain. */
    fun resolveDay(state: RecordState, dayKey: String, holidays: HolidayCalendar): DayResolution {
        val period = DayRecordResolver.period(dayKey, state.periods)
        val snapshot = period?.let { DayRecordResolver.snapshot(dayKey, it, state.snapshots) }
        val expansion = if (period != null && snapshot != null) expansion(state, snapshot, period, dayKey, holidays) else ScheduleExpansion.NONE
        return DayRecordResolver.resolve(dayKey, period, snapshot, DayRecordLookup(state.exceptions, state.overrides), expansion)
    }
}
