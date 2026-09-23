package com.rainif.doneat.core.domain.schedule

import com.rainif.doneat.core.domain.salary.SalaryRules
import com.rainif.doneat.core.domain.salary.SalarySettings
import java.time.ZoneId
import kotlin.math.max
import kotlin.math.min

/**
 * Shift resolution, snapshots, Widget shifts and range expansion: the Kotlin
 * port of `lib/countdown.ts` as exposed by `scripts/ios-schedule-rule-oracle.mjs`
 * (Swift: `ScheduleRules` and `ShiftRuleCore`). The TypeScript is the
 * specification; `ScheduleRuleFixtureTest` holds this to its cases. Change a
 * shared rule in `lib/`, Swift and here together, then regenerate fixtures.
 */
object ScheduleRules {
    fun snapshot(input: ScheduleRuleInput, salary: SalarySettings): ShiftSnapshot {
        val zone = zoneFor(input)
        val shift = resolveCurrentShift(input, zone)
        val nextShift = nextShift(shift, input, zone)
        val clockIn = countdownProjection(input, shift, nextShift, zone)
        val dailySalary = SalaryRules.dailySalary(salary)
        val payRatio = shift.payRatio(input.nowMs)
        return ShiftSnapshot(
            segments = shift.segments,
            startAtMs = shift.startAtMs,
            endAtMs = shift.endAtMs,
            plannedEndAtMs = shift.plannedEndAtMs,
            overtimeEndAtMs = shift.overtimeEndAtMs,
            durationMs = shift.durationMs,
            plannedDurationMs = shift.plannedDurationMs,
            elapsedMs = shift.elapsedMs(input.nowMs),
            remainingMs = shift.remainingMs(input.nowMs),
            progress = shift.progress(input.nowMs),
            payRatio = payRatio,
            activeBreakEndAtMs = shift.activeBreakEndAtMs(input.nowMs),
            isWorkday = zone.isScheduledWorkday(shift.startAtMs, input.workdays, input.schedule),
            nextRestAtMs = zone.nextRestDayStartMs(input.nowMs, input.workdays, input.schedule),
            dailySalary = dailySalary,
            earnedSoFar = dailySalary?.let { max(0.0, payRatio) * it },
            nextShiftStartAtMs = nextShift?.startAtMs,
            nextShiftEndAtMs = nextShift?.endAtMs,
            countdownTargetAtMs = clockIn.targetAtMs,
            countdownAnchorAtMs = clockIn.anchorAtMs,
            countdownProgress = clockIn.progress,
        )
    }

    /**
     * Every scheduled shift after the current one, through the first shift
     * that starts at or after `throughMs`. That last one is kept as a
     * countdown target even though a widget never draws it.
     */
    fun widgetShifts(input: ScheduleRuleInput, throughMs: Double, maximumCount: Int): List<WidgetShift> {
        val zone = zoneFor(input)
        val options = ShiftOptions.of(input)
        val current = zone.shiftTimeline(input.startTime, input.endTime, input.nowMs, options)
        val shifts = ArrayList<WidgetShift>()
        var afterMs = max(input.nowMs, current.endAtMs)
        while (shifts.size < max(0, maximumCount)) {
            val shift = zone.nextShiftTimeline(input.hours, afterMs, options.withoutOvertime()) ?: break
            shifts += WidgetShift(
                segments = shift.segments,
                startAtMs = shift.startAtMs,
                endAtMs = shift.endAtMs,
                plannedEndAtMs = shift.plannedEndAtMs,
                overtimeEndAtMs = shift.overtimeEndAtMs,
                durationMs = shift.durationMs,
                countdownAnchorAtMs = countdownAnchorAtMs(input, shift.startAtMs, zone),
            )
            if (shift.startAtMs >= throughMs || shift.endAtMs <= afterMs) break
            afterMs = shift.endAtMs
        }
        return shifts
    }

    /**
     * Every civil day in `[fromMs, throughMs]` with its planned hours. Rest days
     * still carry segments so a makeup-day exception can reuse them. An overnight
     * shift keys as the day it starts. Manual days are rest.
     */
    fun expandScheduleRange(hours: ScheduleHours, fromMs: Double, throughMs: Double, zoneId: ZoneId): List<ScheduleDayExpansion> {
        val zone = CivilZone(zoneId, hours.extended?.let(::ExtendedScheduleResolver))
        val fromDay = zone.civil(fromMs).dayNumber
        val throughDay = zone.civil(throughMs).dayNumber
        if (throughDay < fromDay) return emptyList()
        return (fromDay..throughDay).map { dayNumber ->
            // Per day: an extended schedule gives each day its own shift.
            val (start, end) = zone.dayClocks(dayNumber, hours.startTime, hours.endTime)
            val (breakStartTime, breakMinutes) = zone.dayBreak(dayNumber, hours.breakStartTime, hours.breakDurationMinutes)
            val breakClock = breakStartTime?.takeIf { it.isNotEmpty() }?.let(WallClock::parse)
            val breakDurationMs = breakMinutes * 60_000.0
            val startAtMs = zone.utcMs(dayNumber, start)
            var endAtMs = zone.utcMs(dayNumber, end)
            if (endAtMs <= startAtMs) {
                endAtMs = if (end.minutes > start.minutes) startAtMs else zone.utcMs(dayNumber + 1, end)
            }
            var segments = listOf(ShiftSegment(startAtMs, endAtMs))
            if (breakClock != null && breakDurationMs > 0) {
                var breakStartAtMs = zone.utcMs(dayNumber, breakClock)
                if (breakStartAtMs < startAtMs) breakStartAtMs = zone.utcMs(dayNumber + 1, breakClock)
                val breakEndAtMs = breakStartAtMs + breakDurationMs
                if (breakStartAtMs > startAtMs && breakEndAtMs < endAtMs) {
                    segments = listOf(ShiftSegment(startAtMs, breakStartAtMs), ShiftSegment(breakEndAtMs, endAtMs))
                }
            }
            ScheduleDayExpansion(
                dayKey = zone.dayKey(startAtMs),
                shiftAnchorStartAtMs = startAtMs,
                isWorkday = zone.isScheduledWorkdayInZone(startAtMs, hours.workdays, hours.schedule),
                segments = segments,
            )
        }
    }

    /** Whether the configured break lands strictly inside the shift. No break is trivially valid. */
    fun validateBreak(input: ScheduleRuleInput): Boolean {
        val breakStartTime = input.hours.breakStartTime
        if (breakStartTime.isNullOrEmpty() || input.hours.breakDurationMinutes <= 0) return true
        return zoneFor(input)
            .shiftTimeline(input.startTime, input.endTime, input.nowMs, ShiftOptions.of(input))
            .segments.size > 1
    }

    /**
     * Whether saving an edit should ask about today: whenever today's shift
     * under the current or the edited settings is a scheduled one.
     */
    fun shouldPromptApplyToday(current: ScheduleRuleInput, candidate: ScheduleRuleInput) =
        listOf(current, candidate).any { input ->
            val zone = zoneFor(input)
            zone.isScheduledWorkday(resolveCurrentShift(input, zone).startAtMs, input.workdays, input.schedule)
        }

    /**
     * The current and next shift's reminders (iOS `ScheduleRules.reminders`).
     * IDs carry the scope and the shift's end, so a rebuilt list keeps the IDs
     * of reminders that did not move and a changed shift gets new ones.
     */
    fun reminders(input: ScheduleRuleInput, reminderInputs: ReminderInputs): List<Reminder> {
        val zone = zoneFor(input)
        val shift = resolveCurrentShift(input, zone)
        fun project(timeline: ShiftTimeline, scope: String): List<Reminder> {
            val prefix = "$scope:${ReminderRules.jsString(timeline.endAtMs)}:"
            return ReminderRules.buildShiftReminders(timeline, reminderInputs).map { it.copy(id = prefix + it.id) }
        }
        val next = nextShift(shift, input, zone)?.let { project(it, "next") }.orEmpty()
        return ReminderRules.sortedByTime(project(shift, "current") + next)
    }

    private fun zoneFor(input: ScheduleRuleInput) =
        CivilZone(input.zone, input.hours.extended?.let(::ExtendedScheduleResolver))

    internal fun resolveCurrentShift(input: ScheduleRuleInput, zone: CivilZone): ShiftTimeline {
        val options = ShiftOptions.of(input)
        val live = zone.shiftTimeline(input.startTime, input.endTime, input.nowMs, options)
        val ended = zone.endedShiftOnEndCalendarDay(
            input,
            options,
            forcedWorkdayStartMs = input.forcedWorkdayStartMs?.takeIf { it != 0.0 },
        )
        // Last night's overnight only settles until tonight's window starts; a
        // rest-day 22:00–06:00 would otherwise stay pinned to Friday's 06:00 end.
        val liveIsOpen = input.nowMs >= live.startAtMs && input.nowMs < live.endAtMs
        if (ended != null && ended.startAtMs != live.startAtMs && !liveIsOpen) return ended
        return live
    }

    internal fun nextShift(shift: ShiftTimeline, input: ScheduleRuleInput, zone: CivilZone): ShiftTimeline? =
        zone.nextShiftTimeline(input.hours, max(input.nowMs, shift.endAtMs), ShiftOptions.of(input).withoutOvertime())

    internal fun isActualShift(shift: ShiftTimeline, input: ScheduleRuleInput, zone: CivilZone): Boolean {
        if (zone.isScheduledWorkday(shift.startAtMs, input.workdays, input.schedule)) return true
        val forced = input.forcedWorkdayStartMs ?: return false
        return zone.startOfCivilDayMs(shift.startAtMs) == zone.startOfCivilDayMs(forced)
    }

    /**
     * The rest-day ring starts after the previous shift's settlement day and
     * advances monotonically across the rest interval.
     */
    private fun countdownAnchorAtMs(input: ScheduleRuleInput, targetAtMs: Double, zone: CivilZone): Double {
        val targetDayMs = zone.startOfCivilDayMs(targetAtMs)
        val options = ShiftOptions.of(input).withoutOvertime()
        for (offset in 1..366) {
            // Probe from the middle of the candidate day: from civil midnight an
            // overnight 22:00–06:00 resolves to the previous day's shift.
            val probeMs = zone.addCivilDaysMs(targetDayMs, -offset) + 12 * 3_600_000.0
            val previous = zone.shiftTimeline(input.startTime, input.endTime, probeMs, options)
            if (!zone.isScheduledWorkday(previous.startAtMs, input.workdays, input.schedule)) continue
            val anchorMs = zone.addCivilDaysMs(zone.startOfCivilDayMs(previous.endAtMs), 1)
            if (anchorMs < targetAtMs) return anchorMs
        }
        return targetDayMs
    }

    private data class ClockIn(val targetAtMs: Double?, val anchorAtMs: Double?, val progress: Double)

    private fun countdownProjection(
        input: ScheduleRuleInput,
        shift: ShiftTimeline,
        nextShift: ShiftTimeline?,
        zone: CivilZone,
    ): ClockIn {
        val targetAtMs = if (input.nowMs < shift.startAtMs && isActualShift(shift, input, zone)) {
            shift.startAtMs
        } else {
            nextShift?.startAtMs
        }
        if (targetAtMs == null || targetAtMs <= input.nowMs) return ClockIn(null, null, 0.0)

        val targetDayAtMs = zone.startOfCivilDayMs(targetAtMs)
        val isTargetWorkday = input.nowMs >= targetDayAtMs
        val anchorAtMs = if (isTargetWorkday) targetDayAtMs else countdownAnchorAtMs(input, targetAtMs, zone)
        val progressEndAtMs = if (isTargetWorkday) targetAtMs else targetDayAtMs
        val durationMs = progressEndAtMs - anchorAtMs
        val progress = if (durationMs > 0) {
            max(0.0, min(100.0, (input.nowMs - anchorAtMs) / durationMs * 100))
        } else {
            0.0
        }
        return ClockIn(targetAtMs, anchorAtMs, progress)
    }
}
