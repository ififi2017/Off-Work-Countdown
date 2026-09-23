package com.rainif.doneat.core.domain.session

import com.rainif.doneat.core.domain.records.DayOverride
import com.rainif.doneat.core.domain.records.DayOverrideProjection
import com.rainif.doneat.core.domain.records.FoundationCompat
import com.rainif.doneat.core.domain.schedule.RosterDay
import com.rainif.doneat.core.domain.records.SnapshotHours
import com.rainif.doneat.core.domain.records.SyncedPreferences
import com.rainif.doneat.core.domain.records.TimerDayMarks
import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import com.rainif.doneat.core.domain.schedule.ExtendedSchedule
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleContent
import com.rainif.doneat.core.domain.schedule.ExtendedSchedulePlan
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.ScheduleHours
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ScheduleRuleInput
import com.rainif.doneat.core.domain.schedule.ScheduleRules
import com.rainif.doneat.core.domain.schedule.ShiftSnapshot
import com.rainif.doneat.core.domain.schedule.WorkSchedule
import com.rainif.doneat.core.domain.summary.SummaryRules
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

/** Which settings the rules read. iOS `RulesScheduleSource`. */
enum class RulesSource {
    /** Today's kept hours and an early clock-in, while they still cover the instant. */
    EFFECTIVE,

    /** The committed hours and pattern: future shifts, so "from the next shift only" does not paint old times forward. */
    BASE,
}

/**
 * Everything besides the session's own state that the countdown reads. The
 * extended schedule and roster come from the records archive; the plans built
 * from them are kept for the life of this value, which the store replaces
 * whenever any of its inputs change.
 */
class SessionEnvironment(
    val preferences: SyncedPreferences,
    /** Setup is done; before that there is no schedule to follow. */
    val onboardingComplete: Boolean,
    val extendedSchedule: ExtendedSchedule?,
    val rosterDays: List<RosterDay>,
    val holidays: HolidayCalendar,
    /** The device's zone, which a new manual run adopts when it differs from Records. */
    val deviceZone: String,
    /** Whether use events are written to the archive (Plus decides; free users collect, as on iOS). */
    val collectsObservations: Boolean = true,
) {
    val isExtendedScheduleEnabled get() = extendedSchedule?.isEnabled == true

    /** The stored plan, switched on or not; whether the countdown follows it is the session's call. */
    val livePlan: ExtendedSchedulePlan? by lazy {
        ExtendedSchedulePlan.of(extendedSchedule, rosterDays, holidays, includeDisabled = true)
    }

    /**
     * Shift types and a rule other than the stored ones over the stored
     * hand-set days (today's kept schedule). Types created since are added,
     * so a day filled in later with a new type still resolves.
     */
    fun plan(content: ExtendedScheduleContent): ExtendedSchedulePlan {
        val live = extendedSchedule
        if (live != null && live.content == content) livePlan?.let { return it }
        val saved = content.shiftTypes.map { it.id }.toSet()
        val liveTypes = live?.content?.shiftTypes.orEmpty()
        return ExtendedSchedulePlan(
            shiftTypes = content.shiftTypes + liveTypes.filter { it.id !in saved },
            rule = content.rule,
            handSetDays = livePlan?.handSetDays ?: ExtendedSchedulePlan.handSetDays(rosterDays),
            holidayRegionIdentifier = content.holidayRegionIdentifier,
            clearedFromDayKey = content.clearedFromDayKey,
            frozenShiftTypes = ExtendedSchedulePlan.frozenShiftTypes(rosterDays),
            holidays = holidays,
        )
    }

    /** The days the user gave a shift by hand, by civil day key. */
    val handSetDays: Map<String, UUID> get() = livePlan?.handSetDays ?: ExtendedSchedulePlan.handSetDays(rosterDays)

    /** Days a pattern preview wrote out, which "clear expected days" may remove again. */
    val generatedRosterDays: Set<String> get() = rosterDays.filter { it.generatedFromPattern == true }.map { it.dayKey }.toSet()

    /** A schedule page draft as the rules would read it once saved. */
    fun plan(content: ExtendedScheduleContent?, edits: Map<String, RosterDayEdit>?): ExtendedSchedulePlan? {
        content ?: return null
        val base = plan(content)
        if (edits.isNullOrEmpty()) return base
        return ExtendedSchedulePlan(
            base.shiftTypes, base.rule, ScheduleEditing.handSetDays(base.handSetDays, edits), base.holidayRegionIdentifier,
            base.clearedFromDayKey, base.holidayOverrides, base.frozenShiftTypes.filterKeys { it !in edits },
            base.fallsBackToBaseSchedule, base.pinnedDayKey, base.holidays,
        )
    }

    /** The same environment over a newer archive (its settings, schedule and calendar). */
    fun with(records: com.rainif.doneat.core.domain.records.RecordState) = SessionEnvironment(
        records.syncedPreferences?.takeIf { it.isValid } ?: preferences, onboardingComplete, records.extendedSchedule, records.rosterDays,
        holidays, deviceZone, collectsObservations,
    )

    /** [plan] with one day as it was before a save. */
    fun planKeeping(plan: ExtendedSchedulePlan, day: KeptRosterDay): ExtendedSchedulePlan {
        if (plan.handSetDays[day.dayKey] == day.shiftTypeID) return plan
        val days = plan.handSetDays.toMutableMap()
        if (day.shiftTypeID == null) days.remove(day.dayKey) else days[day.dayKey] = day.shiftTypeID
        return ExtendedSchedulePlan(
            plan.shiftTypes, plan.rule, days, plan.holidayRegionIdentifier, plan.clearedFromDayKey, plan.holidayOverrides,
            plan.frozenShiftTypes, plan.fallsBackToBaseSchedule, plan.pinnedDayKey, plan.holidays,
        )
    }
}

/**
 * The running countdown's read projections (iOS `ShiftSession`): which
 * settings apply at an instant, the rules snapshot, and what the timer shows.
 * Pure: it holds one [SessionState] and one [SessionEnvironment] and reads no
 * clock; every instant is passed in.
 */
class ShiftSession(val state: SessionState, val env: SessionEnvironment) {
    private val prefs get() = env.preferences

    val scheduleMode: ScheduleMode get() = ScheduleMode.fromRaw(prefs.scheduleMode) ?: ScheduleMode.CLASSIC

    val recordsZone: ZoneId get() = FoundationCompat.javaZone(prefs.recordsTimeZoneIdentifier)

    /** The zone the running countdown uses: a manual run's own, otherwise Records'. */
    val countdownZoneId: String get() = state.sessionTimeZone ?: prefs.recordsTimeZoneIdentifier
    val countdownZone: ZoneId get() = FoundationCompat.javaZone(countdownZoneId)

    val deviceZone: ZoneId get() = FoundationCompat.javaZone(env.deviceZone)

    val salary: SalarySettings
        get() = SalarySettings(
            amount = if (prefs.salaryEnabled) prefs.salaryAmount else "",
            type = SalaryType.fromRaw(prefs.salaryType),
            monthlyWorkingDays = prefs.monthlyWorkingDays,
            annualBonusMonths = if (prefs.annualBonusEnabled) prefs.annualBonusMonths else 0.0,
        )

    /** A new manual run adopts the device's zone when it differs from Records. */
    fun timeZoneIdentifierForWriting(startingNewSession: Boolean = false): String =
        if (startingNewSession && env.deviceZone != prefs.recordsTimeZoneIdentifier) env.deviceZone else countdownZoneId

    // Which settings apply

    fun usesTodayOverride(nowMs: Double): Boolean = state.todayOverride?.let { nowMs < it.untilMs } == true

    fun isStartedEarly(nowMs: Double): Boolean {
        val at = state.earlyStartAtMs ?: return false
        val until = state.earlyStartUntilMs ?: return false
        return nowMs >= at && nowMs < until
    }

    /** Future projections must not inherit today's early clock-in or kept hours. */
    fun projectsFutureFromBase(nowMs: Double) = usesTodayOverride(nowMs) || isStartedEarly(nowMs)

    fun effectiveScheduleMode(nowMs: Double): ScheduleMode {
        if (!usesTodayOverride(nowMs)) return scheduleMode
        return state.todayOverride?.scheduleMode?.let(ScheduleMode::fromRaw) ?: scheduleMode
    }

    fun effectiveStartMinutes(nowMs: Double): Int {
        val early = state.earlyStartAtMs
        if (isStartedEarly(nowMs) && early != null) return minutes(early, countdownZone)
        return state.todayOverride?.takeIf { usesTodayOverride(nowMs) }?.startMinutes ?: prefs.startMinutes
    }

    fun effectiveEndMinutes(nowMs: Double) = kept(nowMs)?.endMinutes ?: prefs.endMinutes

    fun effectiveWorkdays(nowMs: Double) = kept(nowMs)?.workdays?.toSet() ?: prefs.workdays.toSet()

    fun effectiveLunchEnabled(nowMs: Double) = kept(nowMs)?.lunchEnabled ?: prefs.lunchEnabled

    fun effectiveLunchStartMinutes(nowMs: Double) = kept(nowMs)?.lunchStartMinutes ?: prefs.lunchStartMinutes

    fun effectiveLunchDurationMinutes(nowMs: Double) = kept(nowMs)?.lunchDurationMinutes ?: prefs.lunchDurationMinutes

    private fun kept(nowMs: Double) = state.todayOverride?.takeIf { usesTodayOverride(nowMs) }

    /** Whether the rules follow the extended schedule; today keeps the setting it had when a change was saved for later. */
    fun usesExtendedSchedule(nowMs: Double, source: RulesSource = RulesSource.EFFECTIVE): Boolean {
        if (source == RulesSource.EFFECTIVE && usesTodayOverride(nowMs)) {
            state.todayOverride?.extendedScheduleEnabled?.let { return it }
        }
        return env.isExtendedScheduleEnabled
    }

    fun extendedSchedulePlan(nowMs: Double, source: RulesSource = RulesSource.EFFECTIVE): ExtendedSchedulePlan? {
        if (!usesExtendedSchedule(nowMs, source)) return null
        val kept = state.todayOverride
        if (source != RulesSource.EFFECTIVE || !usesTodayOverride(nowMs) || kept == null) return env.livePlan
        val plan = kept.extendedContent?.let(env::plan) ?: env.livePlan ?: return null
        val day = kept.extendedKeptDay ?: return plan
        return env.planKeeping(plan, day)
    }

    val forcedWorkdayStartMs: Double?
        get() {
            val date = state.forcedWorkdayDate?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: return null
            return date.atStartOfDay(countdownZone).toInstant().toEpochMilli().toDouble()
        }

    fun followsSchedule(nowMs: Double) = env.onboardingComplete && effectiveScheduleMode(nowMs) != ScheduleMode.OFF

    fun shouldQuerySnapshot(nowMs: Double) = followsSchedule(nowMs) || state.countdownStarted

    // Rules input

    fun workSchedule(nowMs: Double, source: RulesSource = RulesSource.EFFECTIVE): WorkSchedule {
        val o = state.todayOverride?.takeIf { source == RulesSource.EFFECTIVE && usesTodayOverride(nowMs) }
        val mode = if (o != null) effectiveScheduleMode(nowMs) else scheduleMode
        return WorkSchedule(
            mode = mode,
            referenceWeekStartMs = if (mode == ScheduleMode.ALTERNATING) o?.alternatingReferenceWeekStartMs ?: prefs.alternatingReferenceWeekStartMs else null,
            referenceWeekType = if (mode == ScheduleMode.ALTERNATING) o?.alternatingWeekType ?: prefs.alternatingWeekType else null,
            singleWeekendWorkday = if (mode == ScheduleMode.ALTERNATING) o?.alternatingWeekendWorkday ?: prefs.alternatingWeekendWorkday else null,
            rotationAnchorMs = if (mode == ScheduleMode.ROTATION) o?.rotationAnchorMs ?: prefs.rotationAnchorMs else null,
            rotationWorkDays = if (mode == ScheduleMode.ROTATION) o?.rotationWorkDays ?: prefs.rotationWorkDays else null,
            rotationRestDays = if (mode == ScheduleMode.ROTATION) o?.rotationRestDays ?: prefs.rotationRestDays else null,
        )
    }

    /**
     * The rules input at [nowMs]. [startMinutes]/[endMinutes] fix the current
     * shift's readings (a draft, or an early clock-in); under an extended
     * schedule that pins the current shift's day instead of replacing the roster.
     */
    fun rulesInput(
        nowMs: Double,
        startMinutes: Int? = null,
        endMinutes: Int? = null,
        source: RulesSource = RulesSource.EFFECTIVE,
        pinsEarlyStart: Boolean = true,
    ): ScheduleRuleInput {
        val apply = source == RulesSource.EFFECTIVE
        val earlyStart = pinsEarlyStart && apply && startMinutes == null && isStartedEarly(nowMs)
        val start = startMinutes ?: if (apply) effectiveStartMinutes(nowMs) else prefs.startMinutes
        val end = endMinutes ?: if (apply) effectiveEndMinutes(nowMs) else prefs.endMinutes
        val lunchOn = if (apply) effectiveLunchEnabled(nowMs) else prefs.lunchEnabled
        val hours = ScheduleHours(
            startTime = timeString(start),
            endTime = timeString(end),
            workdays = (if (apply) effectiveWorkdays(nowMs) else prefs.workdays.toSet()).sorted(),
            schedule = workSchedule(nowMs, source),
            breakStartTime = if (lunchOn) timeString(if (apply) effectiveLunchStartMinutes(nowMs) else prefs.lunchStartMinutes) else null,
            breakDurationMinutes = if (lunchOn) (if (apply) effectiveLunchDurationMinutes(nowMs) else prefs.lunchDurationMinutes) else 0,
            extended = extendedSchedulePlan(nowMs, source),
        )
        val input = ScheduleRuleInput(
            hours = hours,
            nowMs = nowMs,
            zone = countdownZone,
            overtimeEndAtMs = if (apply) state.overtimeEndAtMs else null,
            forcedWorkdayStartMs = if (apply) forcedWorkdayStartMs else null,
        )
        return pinningCurrentShift(input, fixesStart = startMinutes != null || earlyStart, fixesEnd = endMinutes != null)
    }

    /**
     * An assigned day brings its own clock readings, which would replace the
     * ones fixed for the current shift. Fix that shift's day instead; nothing is stored.
     */
    private fun pinningCurrentShift(input: ScheduleRuleInput, fixesStart: Boolean, fixesEnd: Boolean): ScheduleRuleInput {
        val plan = input.hours.extended ?: return input
        if (!fixesStart && !fixesEnd) return input
        val planned = ScheduleRules.snapshot(input, salary)
        val dayKey = dayKey(planned.startAtMs, countdownZone)
        // A rest day already takes the fixed readings through its fallback hours.
        var hours = plan.hours(dayKey) ?: return input
        if (fixesStart) hours = hours.copy(startTime = input.startTime)
        if (fixesEnd) hours = hours.copy(endTime = input.endTime)
        return input.copy(hours = input.hours.copy(extended = plan.pinning(dayKey, hours)))
    }

    /** The current shift at [nowMs]; null only when the rules cannot resolve one. */
    fun snapshot(nowMs: Double, startMinutes: Int? = null, endMinutes: Int? = null): ShiftSnapshot? = runCatching {
        val result = ScheduleRules.snapshot(rulesInput(nowMs, startMinutes, endMinutes), salary)
        if (startMinutes == null && endMinutes == null && projectsFutureFromBase(nowMs)) {
            result.withProjectedFuture(ScheduleRules.snapshot(rulesInput(nowMs, source = RulesSource.BASE), salary), deviceZone)
        } else {
            result
        }
    }.getOrNull()

    /** The hours a Records snapshot stores: committed settings, no overtime, no instant, no salary. */
    fun hoursConfiguration(nowMs: Double): SnapshotHours {
        val input = rulesInput(nowMs, source = RulesSource.BASE)
        return SnapshotHours.of(input.hours, if (input.hours.extended == null) null else env.extendedSchedule?.content)
    }

    // Marks on the current shift

    /** Whether [shift] is a rest day worked anyway, keyed on the day it starts. */
    fun isForcedWorkday(shift: ShiftSnapshot): Boolean {
        val forced = state.forcedWorkdayDate ?: return false
        return forced == dayKey(shift.startAtMs, countdownZone)
    }

    /** Whether the user already ended [shift] by hand, compared against its own window. */
    fun isEndedEarly(shift: ShiftSnapshot): Boolean {
        val at = state.earlyOffAtMs ?: return false
        val shiftEnd = state.earlyOffShiftEndAtMs ?: return false
        return shift.endAtMs > at && shift.startAtMs < shiftEnd
    }

    /** The shift as it stood at clock-off; next-shift figures stay live. */
    fun clockOffSnapshot(shift: ShiftSnapshot): ShiftSnapshot {
        if (!isEndedEarly(shift)) return shift
        return state.earlyOffSnapshot?.withProjectedFuture(shift, deviceZone) ?: shift
    }

    fun isShiftComplete(shift: ShiftSnapshot) = shift.remainingMs <= 0 || isEndedEarly(shift)

    fun visualPhase(snapshot: ShiftSnapshot?, nowMs: Double) = TimerPhase.resolve(
        followsSchedule = followsSchedule(nowMs),
        sessionActive = state.countdownStarted,
        snapshot = snapshot,
        forceToday = snapshot?.let(::isForcedWorkday) ?: false,
        endedEarly = snapshot?.let(::isEndedEarly) ?: false,
        nowMs = nowMs,
    )

    fun visualPhase(nowMs: Double) = visualPhase(if (shouldQuerySnapshot(nowMs)) snapshot(nowMs) else null, nowMs)

    /** Until the next clock-in the screen is counting to. */
    fun countdownToClockInMs(snapshot: ShiftSnapshot, nowMs: Double): Double {
        if ((snapshot.isWorkday || isForcedWorkday(snapshot)) && snapshot.isBeforeStart(nowMs)) return snapshot.heroRemainingMs(nowMs)
        snapshot.nextShiftStartAtMs?.let { return maxOf(0.0, it - nowMs) }
        return snapshot.heroRemainingMs(nowMs)
    }

    /** Elapsed progress toward the next clock-in, from the rules' stable anchor. */
    fun countdownToClockInProgress(snapshot: ShiftSnapshot) = snapshot.countdownProgress.coerceIn(0.0, 100.0)

    /** Hours without an early clock-in, so the projection applies that bound once. */
    fun scheduleStartMinutes(nowMs: Double): Int {
        if (usesExtendedSchedule(nowMs)) {
            val planned = ScheduleRules.snapshot(rulesInput(nowMs, pinsEarlyStart = false), salary)
            return minutes(planned.startAtMs, countdownZone)
        }
        return kept(nowMs)?.startMinutes ?: prefs.startMinutes
    }

    fun timerDayMarks(nowMs: Double, workday: Boolean? = null): TimerDayMarks {
        val current = snapshot(nowMs)
        val endedEarly = current?.let(::isEndedEarly) ?: false
        return TimerDayMarks(
            earlyStartAtMs = if (isStartedEarly(nowMs)) state.earlyStartAtMs else null,
            earlyOffAtMs = if (endedEarly) state.earlyOffAtMs else null,
            forcedWorkdayDate = state.forcedWorkdayDate,
            hasTodayOverride = usesTodayOverride(nowMs),
            hasUnscheduledSession = state.countdownStarted && effectiveScheduleMode(nowMs) == ScheduleMode.OFF,
            isWorkday = workday ?: (current?.isWorkday == true),
        )
    }

    /** The live timer's marks as a Records day override, or null when today still follows the schedule. */
    fun projectedDayOverride(nowMs: Double): DayOverride? {
        val useBaseStart = isStartedEarly(nowMs)
        val shift = snapshot(nowMs, startMinutes = if (useBaseStart) scheduleStartMinutes(nowMs) else null)
        val marks = timerDayMarks(nowMs, workday = shift?.isWorkday == true)
        shift ?: return null
        val zone = timeZoneIdentifierForWriting()
        return DayOverrideProjection.project(marks, dayKey(shift.startAtMs, FoundationCompat.javaZone(zone)), shift.segments, zone)
    }

    /** Whether today's break sits inside the hours; each extended shift type validates its own. */
    fun isLunchInsideShift(nowMs: Double, startMinutes: Int? = null, endMinutes: Int? = null): Boolean {
        if (usesExtendedSchedule(nowMs)) return true
        return !prefs.lunchEnabled || ScheduleRules.validateBreak(rulesInput(nowMs, startMinutes, endMinutes))
    }

    /**
     * Where "from the next shift only" hands over: the day after the current
     * shift ends, or after today on a rest day or unscheduled idle.
     */
    fun overrideExpiry(nowMs: Double): Double {
        snapshot(nowMs)?.let { shift ->
            val inShift = shift.isWorkday || isForcedWorkday(shift) || isEndedEarly(shift) ||
                (state.countdownStarted && scheduleMode == ScheduleMode.OFF)
            if (inShift) return startOfNextDayMs(shift.endAtMs, recordsZone)
        }
        return startOfNextDayMs(nowMs, recordsZone)
    }

    /** The break the rules placed in [snapshot] once it has been taken, as of [nowMs] or the clock-off. */
    fun takenLunchWindow(snapshot: ShiftSnapshot, nowMs: Double): Pair<Double, Double>? {
        val window = snapshot.segments.zipWithNext().firstOrNull { (a, b) -> b.startAtMs > a.endAtMs }
            ?.let { (a, b) -> a.endAtMs to b.startAtMs } ?: return null
        val cutoff = if (isEndedEarly(snapshot)) state.earlyOffAtMs ?: nowMs else nowMs
        return window.takeIf { cutoff >= it.second }
    }

    /**
     * The week or year so far, estimated from the schedule. Null without a
     * schedule to estimate from. A rest day worked anyway counts, with the
     * hours it was worked on.
     */
    fun periodSummary(period: SummaryRules.Period, asOfMs: Double, snapshot: ShiftSnapshot, periodStartMs: Double? = null): SummaryRules.PeriodSummary? {
        val extended = usesExtendedSchedule(asOfMs)
        if (!extended && effectiveScheduleMode(asOfMs) == ScheduleMode.OFF) return null
        val workdays = effectiveWorkdays(asOfMs).toMutableSet()
        var plan = if (extended) extendedSchedulePlan(asOfMs) else null
        if (isForcedWorkday(snapshot)) {
            // iOS reads the weekday in the device calendar.
            workdays += Instant.ofEpochMilli(snapshot.startAtMs.toLong()).atZone(deviceZone).dayOfWeek.value % 7
            plan?.let { current ->
                val day = dayKey(snapshot.startAtMs, countdownZone)
                if (current.hours(day) == null) {
                    val input = rulesInput(asOfMs)
                    plan = current.pinning(
                        day,
                        com.rainif.doneat.core.domain.schedule.ExtendedScheduleDayHours(
                            input.startTime, input.endTime, input.hours.breakStartTime, input.hours.breakDurationMinutes,
                        ),
                    )
                }
            }
        }
        return SummaryRules.summarize(
            SummaryRules.SummaryInput(
                period = period,
                periodStartMs = periodStartMs,
                asOfMs = asOfMs,
                workdays = workdays.sorted(),
                schedule = workSchedule(asOfMs),
                currentShiftStartMs = snapshot.startAtMs,
                currentShiftEndMs = snapshot.endAtMs,
                plannedDailyHours = snapshot.plannedDurationMs / 3_600_000,
                todayProgress = minOf(100.0, snapshot.progress),
                dailySalary = snapshot.dailySalary,
                todayEffectiveHours = snapshot.durationMs / 3_600_000,
                todayPayRatio = snapshot.payRatio,
                zone = recordsZone,
                extended = plan,
            ),
        )
    }

    companion object {
        fun timeString(minutes: Int) = "%02d:%02d".format(Locale.ROOT, (minutes / 60) % 24, minutes % 60)

        fun minutes(atMs: Double, zone: ZoneId): Int {
            val t = Instant.ofEpochMilli(atMs.toLong()).atZone(zone)
            return t.hour * 60 + t.minute
        }

        fun dayKey(atMs: Double, zone: ZoneId): String =
            FoundationCompat.dayKey(Instant.ofEpochMilli(atMs.toLong()).atZone(zone).toLocalDate())

        fun startOfNextDayMs(atMs: Double, zone: ZoneId): Double =
            Instant.ofEpochMilli(atMs.toLong()).atZone(zone).toLocalDate().plusDays(1)
                .atStartOfDay(zone).toInstant().toEpochMilli().toDouble()

        /** The instant floored to its minute in [zone]; zones with sub-minute offsets keep their own minute. */
        fun floorToMinute(atMs: Double, zone: ZoneId): Double =
            Instant.ofEpochMilli(atMs.toLong()).atZone(zone).withSecond(0).withNano(0).toInstant().toEpochMilli().toDouble()
    }
}
