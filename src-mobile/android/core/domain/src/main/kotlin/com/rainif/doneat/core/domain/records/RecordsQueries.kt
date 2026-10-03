package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.ExtendedSchedulePlan
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.ScheduleHours
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ScheduleRules
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.WallClock
import com.rainif.doneat.core.domain.schedule.WorkSchedule
import com.rainif.doneat.core.domain.summary.SummaryRules
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import kotlin.math.max

/**
 * Read-only projections of one archive revision (iOS `RecordsQueries`). It
 * never edits the archive and holds no clock: every question takes `nowMs`.
 * Build a new one when the archive, the records zone, Plus or the salary
 * settings change; its caches belong to that one revision.
 *
 * Days are records-zone civil dates. Stored rows keep their own civil labels,
 * so a day is looked up by its label rather than re-derived from an instant.
 */
class RecordsQueries(
    val state: RecordState,
    private val holidays: HolidayCalendar,
    val zone: ZoneId,
    val authorized: Boolean,
    /** Set only while salary is shown; null keeps every amount out of the result. */
    private val salary: SalarySettings? = null,
    /** The current shift's daily pay, for the actual and forecast split. */
    private val dailySalary: Double? = null,
    /** The day owning the running shift, if the countdown is running. */
    private val activeAnchorDayKey: String? = null,
    /** The live schedule's hours: the life projection's stand-in for years before Records. */
    private val currentHours: SnapshotHours? = null,
    val firstDayOfWeek: DayOfWeek = DayOfWeek.MONDAY,
) {
    // Indexes, each built once for this revision.

    /** Observations by their shift-anchor day, oldest first. */
    val observationIndex: Map<String, List<WorkObservation>> by lazy {
        state.observations.groupBy { it.shiftAnchorDate }.mapValues { (_, list) -> list.sortedBy { it.occurredAtMs } }
    }

    /**
     * Every civil day with a user-authored fact: a work observation, an active
     * correction or a user calendar exception. Broader than workday totals on
     * purpose, so leave and rest entries can still be found.
     */
    val recordDayIndex: List<RecordDayIndexEntry> by lazy {
        val entries = linkedMapOf<String, RecordDayIndexEntry>()
        fun entry(key: String) = entries.getOrPut(key) { RecordDayIndexEntry(key) }
        for (o in state.observations) {
            if (o.kind == WorkObservationKind.TIMER_SURFACE_FIRST_SEEN) continue
            entries[o.shiftAnchorDate] = entry(o.shiftAnchorDate).let { it.copy(observations = it.observations + o) }
        }
        for (o in state.overrides) {
            if (o.kind == DayOverrideKind.CLEARED) continue
            entries[o.dayKey] = entry(o.dayKey).copy(dayOverride = o)
        }
        for (e in state.exceptions) {
            if (e.origin != CalendarExceptionOrigin.USER || e.isCleared) continue
            val key = e.dayKey.substringBefore('#')
            if (!DAY_KEY.matches(key)) continue
            entries[key] = entry(key).copy(calendarException = e)
        }
        entries.values.map { it.copy(observations = it.observations.sortedBy { o -> o.occurredAtMs }) }.sortedByDescending { it.dayKey }
    }

    private val recordedDayKeys: Set<String> by lazy { recordDayIndex.map { it.dayKey }.toSet() }
    private val correctedDayKeys: Set<String> by lazy { state.overrides.filter { it.kind != DayOverrideKind.CLEARED }.map { it.dayKey }.toSet() }

    fun isRecordedDay(dayKey: String) = dayKey in recordedDayKeys

    fun today(nowMs: Double): LocalDate = java.time.Instant.ofEpochMilli(nowMs.toLong()).atZone(zone).toLocalDate()

    fun dayStartMs(day: LocalDate) = day.atStartOfDay(zone).toInstant().toEpochMilli().toDouble()

    // Windows

    /** The dates a scale shows around [anchor]; a week starts on the language's first weekday. */
    fun window(scale: RecordsScale, anchor: LocalDate): Pair<LocalDate, LocalDate> = when (scale) {
        RecordsScale.WEEK -> anchor.with(TemporalAdjusters.previousOrSame(firstDayOfWeek)).let { it to it.plusDays(6) }
        RecordsScale.MONTH -> anchor.withDayOfMonth(1).let { it to it.plusMonths(1).minusDays(1) }
        RecordsScale.YEAR -> anchor.withDayOfYear(1).let { it to it.plusYears(1).minusDays(1) }
        RecordsScale.LIFE -> anchor to anchor
    }

    fun shiftAnchor(anchor: LocalDate, scale: RecordsScale, by: Long): LocalDate = when (scale) {
        RecordsScale.WEEK -> anchor.plusWeeks(by)
        RecordsScale.MONTH -> anchor.plusMonths(by)
        RecordsScale.YEAR -> anchor.plusYears(by)
        RecordsScale.LIFE -> anchor
    }

    /** Blank cells a month grid needs before its first day. */
    fun gridLeadingBlanks(first: LocalDate) = (first.dayOfWeek.value - firstDayOfWeek.value + 7) % 7

    // Resolution

    /**
     * Every day in the range through the three-layer chain, over the archive
     * alone: no life projection. A query never seeds or repairs the archive.
     */
    fun resolvedDays(from: LocalDate, through: LocalDate): List<DayResolution> =
        walk(from, through, state.periods, state.snapshots)

    /**
     * Records month, week and year days: the archive, plus the life profile's
     * in-memory history for the years before it. Estimated days never become
     * durable rows.
     */
    fun displayDays(from: LocalDate, through: LocalDate, nowMs: Double): List<DayResolution> {
        val bounds = lifeWorkProjectionBounds ?: return resolvedDays(from, through)
        val (periods, snapshots) = lifeScheduleArchive(bounds.first, nowMs)
        return walk(from, through, periods, snapshots)
    }

    private fun walk(from: LocalDate, through: LocalDate, periods: List<CareerPeriod>, snapshots: List<ScheduleSnapshot>): List<DayResolution> {
        if (through.isBefore(from)) return emptyList()
        val fromKey = FoundationCompat.dayKey(from)
        val throughKey = FoundationCompat.dayKey(through)
        val expansions = expansions(fromKey, throughKey, periods, snapshots)
        val lookup = DayRecordLookup(state.exceptions, state.overrides, state.leaveDays)
        val result = ArrayList<DayResolution>()
        var day = from
        while (!day.isAfter(through)) {
            val key = FoundationCompat.dayKey(day)
            val period = DayRecordResolver.period(key, periods)
            val snapshot = period?.let { DayRecordResolver.snapshot(key, it, snapshots) }
            val expansion = when {
                snapshot != null && snapshot.id in expansions.failures -> ScheduleExpansion.FAILED
                else -> snapshot?.let { expansions.bySnapshot[it.id]?.get(key) } ?: expansions.withoutSnapshot[key] ?: ScheduleExpansion.NONE
            }
            result += DayRecordResolver.resolve(key, period, snapshot, lookup, expansion)
            day = day.plusDays(1)
        }
        return result
    }

    private class Expansions {
        val bySnapshot = mutableMapOf<String, Map<String, ScheduleExpansion>>()
        val failures = mutableSetOf<String>()
        val withoutSnapshot = mutableMapOf<String, ScheduleExpansion>()
    }

    /** One expansion per snapshot over the range, not one per day. */
    private fun expansions(fromKey: String, throughKey: String, periods: List<CareerPeriod>, snapshots: List<ScheduleSnapshot>): Expansions {
        val table = Expansions()
        for (snapshot in snapshots) {
            val period = periods.firstOrNull { it.id == snapshot.periodID } ?: continue
            if (period.startsOn > throughKey || (period.endsBefore != null && period.endsBefore <= fromKey)) continue
            if (snapshot.effectiveFrom > throughKey || snapshot.id in table.bySnapshot || snapshot.id in table.failures) continue
            val hours = RecordHistory.expandableHours(state, snapshot, holidays)
            if (hours == null) {
                table.failures += snapshot.id
                continue
            }
            table.bySnapshot[snapshot.id] = expand(hours, fromKey, throughKey, period.timeZoneIdentifier)
                // The first of two duplicate civil keys (a date-line change) wins.
                .groupBy { it.dayKey }.mapValues { (_, days) -> ScheduleExpansion(days.first().isWorkday, days.first().segments) }
        }
        // Frozen roster rows plan days before any snapshot reached them.
        val plan = ExtendedSchedulePlan.historical(state.rosterDays) ?: return table
        val rosterHours = ScheduleHours("00:00", "00:01", emptyList(), WorkSchedule(ScheduleMode.OFF), null, 0, plan)
        for (key in plan.frozenShiftTypes.keys) {
            if (key < fromKey || key > throughKey) continue
            val period = DayRecordResolver.period(key, periods) ?: continue
            if (DayRecordResolver.snapshot(key, period, snapshots) != null) continue
            val day = expand(rosterHours, key, key, period.timeZoneIdentifier).firstOrNull() ?: continue
            table.withoutSnapshot[key] = ScheduleExpansion(day.isWorkday, day.segments, hasPlannedRoster = true)
        }
        return table
    }

    private fun expand(hours: ScheduleHours, fromKey: String, throughKey: String, zoneIdentifier: String) = run {
        val zone = FoundationCompat.javaZone(zoneIdentifier)
        val civil = CivilZone(zone)
        val from = ExtendedScheduleResolver.dayNumber(fromKey) ?: return@run emptyList()
        val through = ExtendedScheduleResolver.dayNumber(throughKey) ?: return@run emptyList()
        ScheduleRules.expandScheduleRange(hours, civil.utcMs(from, WallClock.MIDNIGHT), civil.utcMs(through, WallClock.MIDNIGHT), zone)
    }

    // Life projection

    /** The career span the life profile describes, as records-zone days. */
    val lifeWorkProjectionBounds: Pair<LocalDate, LocalDate>? by lazy {
        val profile = state.lifeProfile ?: return@lazy null
        val start = profile.workStartedPartial?.let(::calculationAnchor)
            ?: profile.workStartedOn?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
            ?: return@lazy null
        val end = profile.retirementOn?.let(::calculationAnchor) ?: return@lazy null
        if (start < end) start to end else null
    }

    fun isInsideLifeWorkProjection(day: LocalDate): Boolean {
        val (start, end) = lifeWorkProjectionBounds ?: return false
        return !day.isBefore(start) && day.isBefore(end)
    }

    /**
     * The archive with the life profile's estimate added in memory: the live
     * schedule for an empty archive, or for the unknown years before the
     * first period when the current one is still open. Gaps between real
     * periods stay uncovered.
     */
    private fun lifeScheduleArchive(workStart: LocalDate, nowMs: Double): Pair<List<CareerPeriod>, List<ScheduleSnapshot>> {
        val periods = state.periods.toMutableList()
        val snapshots = state.snapshots.toMutableList()
        val hours = currentHours ?: return periods to snapshots
        val startKey = FoundationCompat.dayKey(workStart)
        val encoded = ScheduleHoursCodec.encode(hours)
        fun snapshot(periodID: String) = ScheduleSnapshot(
            LIFE_SNAPSHOT_ID, periodID, startKey, encoded.base64, encoded.fingerprint, nowMs, 1, LIFE_SNAPSHOT_ID,
        )
        if (periods.isEmpty()) {
            periods += CareerPeriod(LIFE_PERIOD_ID, startKey, null, null, zone.id, "gregorian", nowMs, nowMs, 1, LIFE_PERIOD_ID)
            snapshots += snapshot(LIFE_PERIOD_ID)
            return periods to snapshots
        }
        val firstStart = periods.minOf { it.startsOn }
        val current = DayRecordResolver.period(FoundationCompat.dayKey(today(nowMs)), periods)
        if (startKey < firstStart && current != null && current.endsBefore == null) {
            periods += current.copy(id = LIFE_PERIOD_ID, startsOn = startKey, endsBefore = firstStart)
            snapshots += snapshot(LIFE_PERIOD_ID)
        }
        return periods to snapshots
    }

    // Life

    /**
     * Days whose rows were written in a zone no career period uses (iOS
     * `daysRecordedOutsidePeriodTimeZone`); Life marks the weeks holding them.
     */
    fun daysRecordedOutsidePeriodTimeZone(): List<String> {
        val periodZones = state.periods.map { it.timeZoneIdentifier }.toSet()
        val tagged = state.overrides.map { it.dayKey to it.timeZoneIdentifier } +
            state.exceptions.map { it.dayKey to it.timeZoneIdentifier } +
            state.observations.map { it.shiftAnchorDate to it.timeZoneIdentifier }
        return tagged.filter { (_, zone) -> zone !in periodZones }.map { it.first }.toSet().sorted()
    }

    /**
     * The Life model (iOS `LifeSummaryModel.prepareLifeViewModel`): the career
     * walked day by day through the same chain as Records, with the profile's
     * in-memory estimate for the years before Records, then the lifetime
     * income. Null without a birth and retirement to span. It costs a career
     * of days, so callers run it off the main thread.
     *
     * [configuredMonthly] is today's salary as a monthly figure, when salary
     * is shown: it only projects forward; earlier salaries stay as entered.
     */
    fun lifeModel(nowMs: Double, configuredMonthly: Double?): LifeViewModel? {
        val profile = RecordJson.migrateLegacyFields(state.lifeProfile ?: return null)
        val lifeStart = profile.bornOn?.let(LifeDates::anchor) ?: return null
        val lifeEnd = profile.retirementOn?.let(LifeDates::anchor) ?: return null
        if (!lifeEnd.isAfter(lifeStart)) return null
        val configuredWorkStart = profile.workStartedPartial?.let(LifeDates::anchor)
            ?: profile.workStartedOn?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
            ?: lifeStart.plusYears(22)
        val workStart = maxOf(lifeStart, configuredWorkStart)
        val outside = daysRecordedOutsidePeriodTimeZone().toSet()
        val days = if (!workStart.isBefore(lifeEnd)) {
            emptyList()
        } else {
            val (periods, snapshots) = lifeScheduleArchive(workStart, nowMs)
            walk(workStart, lifeEnd.minusDays(1), periods, snapshots).mapNotNull { r ->
                val periodID = r.periodID ?: return@mapNotNull null
                LifeScheduleDay(
                    periodID = periodID,
                    dayKey = r.dayKey,
                    anchorMs = dayStartMs(date(r.dayKey)),
                    segments = r.segments,
                    overtimeSegments = observationIndex[r.dayKey].orEmpty().mapNotNull { RecordsOvertime.declaredSegment(it, r, avoidingRegularWork = true) },
                    isOverride = r.layer == DayResolutionLayer.OVERRIDE && r.segments.isNotEmpty(),
                )
            }
        }
        return LifeViewCalculator.build(profile, days, outside, nowMs, zone).copy(income = lifeIncome(profile, nowMs, configuredMonthly))
    }

    /** iOS `lifeIncomeSummary`: history as entered, the future at today's salary, an optional fixed-ratio step down. */
    private fun lifeIncome(profile: LifeProfile, nowMs: Double, configuredMonthly: Double?): SummaryRules.LifetimeIncome? {
        val retirement = profile.retirementOn?.let(LifeDates::anchor) ?: return null
        val asOf = FoundationCompat.dayKey(today(nowMs))
        fun day(value: PartialCivilDate) = LifeDates.anchor(value)?.let(FoundationCompat::dayKey)
        fun valid(salary: LifeSalary?) = salary != null && with(LifeDates) { salary.isValid() }
        val salary = profile.roughCurrentSalary ?: profile.employmentPeriods.firstOrNull { it.endsOn == null }?.salary
        val projected = configuredMonthly?.takeIf { it > 0 }?.let { LifeSalary(it, LifeSalaryCadence.MONTHLY) } ?: salary
        var currentStartsOn = asOf
        val periods = when (profile.workHistoryMode) {
            LifeWorkHistoryMode.ROUGH -> {
                val start = profile.workStartedPartial ?: LifeDates.suggestedWorkYear(profile)?.let(LifeDates::yearOnly) ?: return null
                if (salary == null || !valid(salary)) return null
                val startsOn = day(start) ?: return null
                currentStartsOn = maxOf(startsOn, asOf)
                listOf(SummaryRules.IncomePeriod(startsOn, asOf, salary.amount, SummaryRules.Cadence.fromRaw(salary.cadence.raw)))
            }
            LifeWorkHistoryMode.DETAILED -> profile.employmentPeriods.mapNotNull { period ->
                if (!valid(period.salary)) return@mapNotNull null
                val startsOn = day(period.startsOn) ?: return@mapNotNull null
                SummaryRules.IncomePeriod(
                    startsOn, period.endsOn?.let(::day) ?: asOf, period.salary.amount, SummaryRules.Cadence.fromRaw(period.salary.cadence.raw),
                )
            }.also { if (it.isEmpty() && !valid(salary)) return null }
        }
        return SummaryRules.lifetimeIncome(
            SummaryRules.LifetimeInput(
                periods = periods,
                currentSalary = projected?.let { SummaryRules.CurrentSalary(it.amount, SummaryRules.Cadence.fromRaw(it.cadence.raw), currentStartsOn) },
                futureIncomeDecline = profile.futureIncomeDecline?.let { decline ->
                    val birthYear = profile.bornOn?.year ?: profile.birthYear ?: return@let null
                    day(LifeDates.yearOnly(birthYear + decline.startsAtAge))?.let { SummaryRules.IncomeDecline(it, decline.retirementRatio) }
                },
                asOf = asOf,
                retirementOn = FoundationCompat.dayKey(retirement),
            ),
        )
    }

    // Cells

    /**
     * A saved schedule in force is the user's standing agreement; app visits
     * are observations, not attendance. Life's estimate never qualifies.
     */
    private fun hasSavedSchedule(r: DayResolution): Boolean {
        if (r.expansionFailed || r.layer == DayResolutionLayer.NONE) return false
        val periodID = r.periodID ?: return false
        val snapshotID = r.snapshotID ?: return false
        return state.periods.any { it.id == periodID && it.startsOn <= r.dayKey && (it.endsBefore == null || r.dayKey < it.endsBefore) } &&
            state.snapshots.any { it.id == snapshotID && it.periodID == periodID && it.effectiveFrom <= r.dayKey }
    }

    private fun date(dayKey: String): LocalDate = LocalDate.parse(dayKey)

    fun dayCell(
        resolution: DayResolution,
        previous: DayResolution?,
        nowMs: Double,
        includesLifeProjection: Boolean = false,
        revealingAll: Boolean = false,
    ): RecordsDayCell {
        val today = today(nowMs)
        val date = date(resolution.dayKey)
        // `revealingAll` is for totals open to everyone (the overtime line):
        // their cells stay inside the query and never reach a view.
        val revealed = revealingAll || RecordsAccess.canRevealDay(date, today, authorized)
        val future = date.isAfter(today)
        val recorded = isRecordedDay(resolution.dayKey)
        val scheduled = !future && hasSavedSchedule(resolution)
        val corrected = resolution.dayKey in correctedDayKeys
        val projected = includesLifeProjection && !recorded && !corrected && !scheduled && isInsideLifeWorkProjection(date)
        val appearance = when {
            !revealed -> RecordsDayAppearance.LOCKED
            future && !recorded -> if (resolution.isScheduledWorkday) RecordsDayAppearance.PLANNED else RecordsDayAppearance.REST
            corrected -> RecordsDayAppearance.CORRECTED
            recorded || (scheduled && resolution.isScheduledWorkday) -> RecordsDayAppearance.RECORDED
            !resolution.isScheduledWorkday -> RecordsDayAppearance.REST
            else -> RecordsDayAppearance.UNRECORDED
        }
        // A 22:00–06:00 shift is two hours of its day and six of the next; both belong on the cells.
        val contributors = contributingShifts(resolution, previous, nowMs, includesLifeProjection)
        val share = if (revealed && contributors.isNotEmpty()) dayAllocation(resolution, contributors, nowMs) else TimeAllocationShare.ZERO
        return RecordsDayCell(
            dayKey = resolution.dayKey,
            date = date,
            appearance = appearance,
            workMs = share.workMs,
            overtimeMs = share.overtimeMs,
            breakMs = share.breakMs,
            freeMs = share.freeMs,
            observationCount = observationIndex[resolution.dayKey]?.size ?: 0,
            isToday = date == today,
            isFuture = future,
            isProjection = projected,
            // Android has no sync, so there is never a sync conflict to flag.
            hasConflict = false,
            isFromSavedSchedule = revealed && scheduled && !recorded && !corrected,
        )
    }

    /** Cells for a window, reading one lead-in day so an overnight shift into its first day is kept. */
    fun cells(days: List<DayResolution>, firstDay: LocalDate, nowMs: Double): List<RecordsDayCell> {
        val firstKey = FoundationCompat.dayKey(firstDay)
        return days.mapIndexedNotNull { index, day ->
            if (day.dayKey < firstKey) null else dayCell(day, days.getOrNull(index - 1), nowMs, includesLifeProjection = true)
        }
    }

    /** Saved schedules continue without daily visits; future days and life history need projection. */
    private fun contributesHours(r: DayResolution, nowMs: Double, includesLifeProjection: Boolean): Boolean {
        if (isRecordedDay(r.dayKey) || r.dayKey in correctedDayKeys) return true
        if (hasSavedSchedule(r)) return !date(r.dayKey).isAfter(today(nowMs)) || includesLifeProjection
        return includesLifeProjection && isInsideLifeWorkProjection(date(r.dayKey))
    }

    /**
     * The shifts allowed to put hours on a civil day: the day itself and the
     * night before, each only if it counts. Every per-day number reads this.
     */
    fun contributingShifts(r: DayResolution, previous: DayResolution?, nowMs: Double, includesLifeProjection: Boolean) =
        listOfNotNull(previous, r).filter { contributesHours(it, nowMs, includesLifeProjection) }

    fun dayAllocation(r: DayResolution, contributors: List<DayResolution>, nowMs: Double) =
        dayCanvasModel(r, contributors, RecordsDaySource.SCHEDULE_ESTIMATE, nowMs).allocation

    // Summary

    /**
     * The period's headline, or null without Plus: a locked summary is never
     * built, so its values cannot reach a view.
     */
    fun headline(cells: List<RecordsDayCell>, days: List<DayResolution>, nowMs: Double): RecordsHeadlineSummary? {
        if (!authorized) return null
        val recordedKeys = cells.filter { it.appearance == RecordsDayAppearance.RECORDED || it.appearance == RecordsDayAppearance.CORRECTED }
            .map { it.dayKey }.toSet()
        val actualForecast = actualForecast(cells, days, nowMs)
        val hasForecast = actualForecast?.let { it.forecast.days > 0 || it.forecast.hours > 0 } == true
        val hasMonthlyIncome = salary?.type == SalaryType.MONTHLY && actualForecast?.total?.earnings != null
        if (recordedKeys.isEmpty() && !hasForecast && !hasMonthlyIncome) return null
        val byKey = days.associateBy { it.dayKey }
        val combined = TimeAllocationShare.combining(recordedShares(cells, days, nowMs))
        // The allocation describes the whole visible period, forecasts and rest days included.
        val periodShares = cells.mapNotNull { cell ->
            val day = byKey[cell.dayKey] ?: return@mapNotNull null
            dayAllocation(day, contributingShifts(day, previousDay(day, byKey), nowMs, includesLifeProjection = true), nowMs)
        }
        val today = today(nowMs)
        val visible = cells.map { it.dayKey }.toSet()
        val completedScheduledWorkdays = days.count { it.dayKey in visible && it.baseScheduleIsWorkday && date(it.dayKey).isBefore(today) }
        return RecordsHeadlineSummary(
            workdays = recordedKeys.size,
            regularWorkMs = combined.workMs,
            overtimeMs = combined.overtimeMs,
            wakingFreeMs = combined.wakingFreeMs,
            estimatedIncome = salary?.let { SummaryRules.recordsIncome(completedScheduledWorkdays, it) },
            completedScheduledWorkdays = completedScheduledWorkdays,
            allocationDays = periodShares.size,
            allocation = TimeAllocationShare.combining(periodShares),
            sleepFromHealth = sleepFromHealth,
            actualForecast = actualForecast,
        )
    }

    /**
     * Each day of [cells] that actually holds recorded time, split at
     * midnight. The headline and the free overtime line both total these, so
     * a free user and a Plus user read the same overtime.
     */
    fun recordedShares(cells: List<RecordsDayCell>, days: List<DayResolution>, nowMs: Double): List<TimeAllocationShare> {
        val recordedKeys = cells.filter { it.appearance == RecordsDayAppearance.RECORDED || it.appearance == RecordsDayAppearance.CORRECTED }
            .map { it.dayKey }.toSet()
        // Observed, corrected and elapsed saved-schedule days count; a day only
        // receiving hours after midnight counts for its time, never as a workday.
        val byKey = days.associateBy { it.dayKey }
        val counted = days.filter { contributesHours(it, nowMs, includesLifeProjection = false) }.map { it.dayKey }.toSet()
        return cells.mapNotNull { cell ->
            val day = byKey[cell.dayKey] ?: return@mapNotNull null
            val contributors = listOfNotNull(previousDay(day, byKey), day).filter { it.dayKey in counted }
            if (contributors.isEmpty()) return@mapNotNull null
            val allocation = dayAllocation(day, contributors, nowMs)
            // A neighbouring record alone does not make this a covered day.
            if (day.dayKey !in recordedKeys && allocation.workMs <= 0 && allocation.overtimeMs <= 0 && allocation.breakMs <= 0) return@mapNotNull null
            allocation
        }
    }

    /**
     * Recorded overtime in the visible period (plan 020 §5). Free users see it
     * too, so it hands out this one number and nothing else. It is the figure
     * the Plus summary prints: the shared summary rules' actual overtime, or
     * the midnight-split total when they have nothing to say. Null when the
     * period recorded none, so the line never prints a zero that only means
     * "no data".
     *
     * [dayKeys] are the period's days; [days] may reach one day earlier for an
     * overnight shift. Days past a free user's window count too: the cells
     * that read them are built here and never leave.
     */
    fun recordedOvertimeMs(days: List<DayResolution>, dayKeys: Set<String>, nowMs: Double): Double? {
        val cells = days.mapIndexedNotNull { index, day ->
            if (day.dayKey !in dayKeys) null else dayCell(day, days.getOrNull(index - 1), nowMs, revealingAll = true)
        }
        val ms = actualForecast(cells, days, nowMs)?.let { it.actualOvertimeHours * 3_600_000 }
            ?: recordedShares(cells, days, nowMs).sumOf { it.overtimeMs }.toDouble()
        return if (ms > 0) ms else null
    }

    /**
     * All overtime ever recorded, for the life scale. Only days that declared
     * overtime can hold any, so only they are resolved, never the projected
     * career. Same rules as a period's line.
     */
    fun lifetimeRecordedOvertimeMs(nowMs: Double): Double? {
        val keys = state.observations.filter { it.kind == WorkObservationKind.OVERTIME_DECLARED }
            .map { it.shiftAnchorDate }.filter { DAY_KEY.matches(it) }.toSet()
        val first = keys.minOrNull()?.let(::date) ?: return null
        val last = keys.maxOrNull()?.let(::date) ?: return null
        val resolved = resolvedDays(first.minusDays(1), last)
        // The day before rides along for an overnight shift; each day goes in
        // once, or two overtime days in a row would count twice.
        val included = mutableSetOf<String>()
        val days = buildList {
            resolved.forEachIndexed { index, day ->
                if (day.dayKey !in keys) return@forEachIndexed
                for (candidate in listOfNotNull(resolved.getOrNull(index - 1), day)) {
                    if (included.add(candidate.dayKey)) add(candidate)
                }
            }
        }
        return recordedOvertimeMs(days, keys, nowMs)
    }

    private fun previousDay(day: DayResolution, index: Map<String, DayResolution>) =
        index[FoundationCompat.dayKey(date(day.dayKey).minusDays(1))]

    /**
     * One row per visible date: corrected, observed or elapsed saved schedule
     * is actual; life history and future schedule rows are forecast. Fixed
     * monthly pay is spread over the visible dates separately, so this never
     * reads as a payslip.
     */
    private fun actualForecast(cells: List<RecordsDayCell>, days: List<DayResolution>, nowMs: Double): SummaryRules.ActualForecast? {
        val cellsByKey = cells.associateBy { it.dayKey }
        val inputs = days.mapNotNull { day ->
            val cell = cellsByKey[day.dayKey] ?: return@mapNotNull null
            recordsSummaryDay(day, cell)
        }
        if (inputs.isEmpty() && salary?.type != SalaryType.MONTHLY) return null
        return SummaryRules.recordsActualForecast(
            SummaryRules.ActualForecastInput(
                days = inputs,
                periodDayKeys = cells.map { it.dayKey },
                dailySalary = if (salary == null) null else dailySalary,
                asOfMs = nowMs,
                salary = salary,
                zone = zone,
            ),
        )
    }

    private fun recordsSummaryDay(day: DayResolution, cell: RecordsDayCell): SummaryRules.RecordsDay? {
        val dayObservations = observationIndex[day.dayKey].orEmpty()
        val hasActualObservation = dayObservations.any { it.kind != WorkObservationKind.TIMER_SURFACE_FIRST_SEEN }
        val actualKind = when {
            cell.appearance == RecordsDayAppearance.CORRECTED -> SummaryRules.ActualKind.CORRECTED
            cell.appearance == RecordsDayAppearance.RECORDED && hasActualObservation -> SummaryRules.ActualKind.OBSERVED
            !cell.isFuture && hasSavedSchedule(day) -> SummaryRules.ActualKind.SCHEDULED
            else -> null
        }
        val isForecast = actualKind == null && (
            cell.isFromSavedSchedule || cell.appearance == RecordsDayAppearance.PLANNED || cell.isProjection ||
                (cell.appearance == RecordsDayAppearance.RECORDED && !hasActualObservation)
            )
        if (actualKind == null && !isForecast) return null
        return SummaryRules.RecordsDay(
            actualKind = actualKind,
            resolvedSegments = day.segments,
            plannedSegments = day.baseScheduleSegments,
            overtimeSegments = if (actualKind == null) emptyList() else overtimeSegments(day),
            observations = dayObservations.mapNotNull {
                when (it.kind) {
                WorkObservationKind.COUNTDOWN_STARTED -> SummaryRules.Observation(true, it.occurredAtMs)
                WorkObservationKind.COUNTDOWN_STOPPED -> SummaryRules.Observation(false, it.occurredAtMs)
                else -> null
                }
            },
            isActiveAnchor = activeAnchorDayKey == day.dayKey,
        )
    }

    /** Civil-day chart figures pass the same Records rule inputs through the same summary oracle. */
    private fun reportElapsedFigures(day: DayResolution, previous: DayResolution?, nowMs: Double, cells: Map<String, RecordsDayCell>): CycleReportFigures {
        val lower = dayStartMs(date(day.dayKey))
        val upper = dayStartMs(date(day.dayKey).plusDays(1))
        fun clip(segments: List<ShiftSegment>) = segments.mapNotNull { segment ->
            val start = maxOf(lower, segment.startAtMs)
            val end = minOf(upper, segment.endAtMs)
            if (end > start) ShiftSegment(start, end) else null
        }
        val inputs = listOfNotNull(previous, day).mapNotNull { contributor ->
            val cell = cells[contributor.dayKey] ?: dayCell(contributor, null, nowMs, revealingAll = true)
            val input = recordsSummaryDay(contributor, cell) ?: return@mapNotNull null
            if (input.actualKind == null) return@mapNotNull null
            input.copy(resolvedSegments = clip(input.resolvedSegments), overtimeSegments = clip(input.overtimeSegments))
        }
        val actual = SummaryRules.recordsActualForecast(SummaryRules.ActualForecastInput(inputs, listOf(day.dayKey),
            null, nowMs, null, zone))
        return CycleReportFigures(actual.actual.days.toInt(), kotlin.math.round(actual.actual.hours * 3_600_000).toLong(),
            kotlin.math.round(actual.actualOvertimeHours * 3_600_000).toLong())
    }

    /** A report uses one archive revision, one clock and the zone carried by its request. */
    fun reportPeriod(kind: CycleReportKind, date: LocalDate) = CycleReportPeriod.containing(date, kind, zone, firstDayOfWeek)

    fun cycleReportSnapshot(period: CycleReportPeriod, nowMs: Double): CycleReportSnapshot? {
        if (!authorized || CycleReportPeriod.fromUrl(period.url) == null) return null
        if (period.zone != zone) return RecordsQueries(state, holidays, period.zone, authorized, salary, dailySalary,
            activeAnchorDayKey, currentHours, firstDayOfWeek).cycleReportSnapshot(period, nowMs)
        val days = displayDays(period.startDate.minusDays(1), period.endDate, nowMs)
        val cells = cells(days, period.startDate, nowMs)
        val figures = CycleReportFigures.fromHeadline(headline(cells, days, nowMs))
        val resolutionIndex = days.withIndex().associate { it.value.dayKey to it.index }
        val cellsByKey = cells.associateBy { it.dayKey }
        val reportDays = cells.map { cell ->
            val index = resolutionIndex.getValue(cell.dayKey)
            val resolution = days[index]
            val previous = days.getOrNull(index - 1)
            val elapsed = if (cell.isFuture) CycleReportFigures() else reportElapsedFigures(resolution, previous, nowMs, cellsByKey)
            val reliable = !cell.isProjection && resolution.layer != DayResolutionLayer.NONE && !resolution.expansionFailed && previous?.expansionFailed != true
            val kind = when {
                cell.isFuture -> CycleReportDayKind.UPCOMING
                elapsed.workedMs > 0 -> CycleReportDayKind.WORK
                reliable && resolution.segments.isEmpty() && previous?.segments.orEmpty().none { it.endAtMs > dayStartMs(cell.date) } -> CycleReportDayKind.REST
                else -> CycleReportDayKind.UNKNOWN
            }
            CycleReportDay(cell.dayKey, cell.date, kind, maxOf(0L, elapsed.workedMs - elapsed.overtimeMs), elapsed.overtimeMs, cell.isToday)
        }

        var longest = 0
        var longestStart: Int? = null
        var run = 0
        reportDays.forEachIndexed { index, day ->
            run = if (day.kind == CycleReportDayKind.REST) run + 1 else 0
            if (run > longest) { longest = run; longestStart = index - run + 1 }
        }
        val elapsed = reportDays.filter { it.kind != CycleReportDayKind.UPCOMING }
        val overtimeDays = elapsed.filter { it.overtimeMs > 0 }
        val overtime = overtimeDays.maxByOrNull { it.overtimeMs }?.let { CycleReportOvertime(elapsed, overtimeDays.size, it) }
        val complete = period.isComplete(nowMs)
        val todayKey = today(nowMs).toString()
        val used = state.leaveDays.filter { it.dayKey in period.dayKeys && it.dayKey <= todayKey }.sumOf { leave ->
            if (leave.dayKey < todayKey) return@sumOf LeaveDay.PORTION_HALF_DAYS[leave.portion] ?: 0
            val resolution = days.firstOrNull { it.dayKey == leave.dayKey } ?: return@sumOf 0
            val halves = com.rainif.doneat.core.domain.leave.LeaveShiftHalves(resolution.baseScheduleSegments)
            val taken = when (leave.leavePortion) {
                com.rainif.doneat.core.domain.schedule.LeavePortion.WHOLE -> listOf(halves.first, halves.second)
                com.rainif.doneat.core.domain.schedule.LeavePortion.FIRST_HALF -> listOf(halves.first)
                com.rainif.doneat.core.domain.schedule.LeavePortion.SECOND_HALF -> listOf(halves.second)
                null -> emptyList()
            }
            taken.count { half -> half.isNotEmpty() && half.maxOf { it.endAtMs } <= nowMs }
        }
        val focus = reportFocus(period, nowMs, if (period.kind == CycleReportKind.YEAR) 1 else 2)
        val months = if (period.kind == CycleReportKind.YEAR) (0L..11L).map { offset ->
            val monthPeriod = reportPeriod(CycleReportKind.MONTH, period.startDate.plusMonths(offset))
            // Reuse the annual resolution rather than resolving the same calendar thirteen times.
            val monthKeys = monthPeriod.dayKeys.toSet()
            val monthCells = cells.filter { it.dayKey in monthKeys }
            val monthFigures = CycleReportFigures.fromHeadline(headline(monthCells, days, nowMs))
            val restCount = reportDays.count { it.dayKey in monthKeys && it.kind == CycleReportDayKind.REST }
            CycleReportMonth(monthPeriod, monthFigures, restCount, reportFocus(monthPeriod, nowMs, 1)?.rounds ?: 0)
        } else emptyList()
        val baseline = if (complete && period.kind != CycleReportKind.YEAR && figures.hasData) {
            val window = if (period.kind == CycleReportKind.WEEK) 4 else 3
            val minimum = if (period.kind == CycleReportKind.WEEK) 2 else 6
            val priors = (1L..window.toLong()).map { offset ->
                val before = period.neighbour(-offset, firstDayOfWeek)
                val earlierDays = displayDays(before.startDate.minusDays(1), before.endDate, nowMs)
                CycleReportFigures.fromHeadline(headline(cells(earlierDays, before.startDate, nowMs), earlierDays, nowMs))
            }
            val usable = priors.filter { it.hasData && it.workdays >= minimum }
            val selected = if (usable.size >= 2) usable else priors.take(1).filter { it.hasData && it.workdays >= minimum }
            selected.takeIf { it.isNotEmpty() }?.let {
                val average = it.sumOf { prior -> prior.workedMs } / it.size
                CycleReportBaseline(it.size, average, figures.workedMs - average)
            }
        } else null
        val pay = figures.income?.let { income ->
            val perHour = if (figures.workedMs >= 3_600_000) income / (figures.workedMs / 3_600_000.0) else null
            val extra = if (salary?.type != SalaryType.MONTHLY && figures.overtimeMs >= 900_000 && figures.workedMs > 0)
                income * figures.overtimeMs / figures.workedMs else null
            CycleReportPay(income, perHour, extra)
        }
        return CycleReportSnapshot(period, reportDays, figures, reportDays.count { it.kind == CycleReportDayKind.REST },
            longest, longestStart, !complete, baseline, overtime,
            if (period.kind == CycleReportKind.YEAR) null else reportAhead(period, nowMs, used), focus, pay, months, used)
    }

    private fun reportFocus(period: CycleReportPeriod, nowMs: Double, minimum: Int): CycleReportFocus? {
        val index = period.dayKeys.withIndex().associate { it.value to it.index }
        val sessions = state.focusSessions.filter { it.kind == FocusSessionKind.FOCUS && it.endReason == FocusEndReason.COMPLETED &&
            (it.endedAtMs ?: it.plannedEndAtMs) <= nowMs && it.anchorDayKey in index }
        if (sessions.size < minimum) return null
        val perDay = MutableList(index.size) { 0 }
        sessions.forEach { perDay[index.getValue(it.anchorDayKey)]++ }
        val icons = state.focusTasks.associate { it.id to it.icon }
        val topIcon = sessions.mapNotNull { icons[it.taskID] }.groupingBy { it }.eachCount().entries
            .sortedWith(compareByDescending<Map.Entry<FocusTaskIcon, Int>> { it.value }.thenBy { it.key.ordinal }).firstOrNull()?.key
        val focused = sessions.sumOf { it.actualDurationSeconds?.times(1_000L) ?: maxOf(0.0, (it.endedAtMs ?: it.plannedEndAtMs) - it.startedAtMs).toLong() }
        return CycleReportFocus(sessions.size, focused, perDay, perDay.indexOf(perDay.max()), topIcon)
    }

    private fun reportAhead(period: CycleReportPeriod, nowMs: Double, used: Int): CycleReportAhead? {
        val reference = period.referenceDate(nowMs)
        val upcoming = resolvedDays(reference, reference.plusDays(28))
        // An overnight tail prevents a full rest day, using the same midnight-split allocation as Records.
        val rest = upcoming.drop(1).mapIndexed { index, day ->
            val previous = upcoming[index]
            val share = dayAllocation(day, listOf(previous, day), dayStartMs(reference.plusDays(29)))
            day.layer != DayResolutionLayer.NONE && share.workMs + share.overtimeMs == 0L && !day.expansionFailed && !previous.expansionFailed
        }
        var nextBreak: CycleReportNextBreak? = null
        var index = 0
        while (index < rest.size) {
            if (!rest[index]) { index++; continue }
            var end = index
            while (end + 1 < rest.size && rest[end + 1]) end++
            if (end - index + 1 >= 3) {
                val start = reference.plusDays(index.toLong() + 1)
                nextBreak = CycleReportNextBreak(start.toString(), start, end - index + 1, index + 1)
                break
            }
            index = end + 1
        }
        val historical = period.isComplete(nowMs)
        val balances = if (historical) emptyList() else com.rainif.doneat.core.domain.leave.LeaveAdoption.budgets(state.leaveBalances, state.leaveDays)
            .filter { it.covers(reference.toEpochDay().toInt()) }
        val remaining = if (!historical && state.leaveBalances.isNotEmpty()) balances.sumOf { it.availableHalfDays } else null
        val ids = balances.map { it.id }.toSet()
        val entitled = if (remaining != null) state.leaveBalances.filter { it.id in ids }.sumOf { it.entitledHalfDays } else null
        if (nextBreak == null && used == 0 && remaining == null) return null
        return CycleReportAhead(used, remaining, entitled, nextBreak, rest, historical)
    }

    // Days

    /** The latest overtime declared on a day, starting no earlier than its regular work ends. */
    fun overtimeSegments(r: DayResolution): List<ShiftSegment> {
        val latest = observationIndex[r.dayKey].orEmpty()
            .filter { it.kind == WorkObservationKind.OVERTIME_DECLARED }
            .maxWithOrNull(compareBy<WorkObservation> { it.occurredAtMs }.thenBy { it.eventID })
            ?: return emptyList()
        return listOfNotNull(RecordsOvertime.declaredSegment(latest, r, avoidingRegularWork = true))
    }

    /** The source of a neighbouring shift reaching into the day on screen. */
    private fun shiftSource(r: DayResolution, nowMs: Double): RecordsDaySource {
        if (r.dayKey in correctedDayKeys) return RecordsDaySource.CORRECTED
        if (isRecordedDay(r.dayKey)) return if (r.layer == DayResolutionLayer.CALENDAR_EXCEPTION) RecordsDaySource.EXCEPTION else RecordsDaySource.RECORDED
        val date = date(r.dayKey)
        if (date.isAfter(today(nowMs))) return RecordsDaySource.PLANNED
        if (hasSavedSchedule(r)) return if (r.layer == DayResolutionLayer.CALENDAR_EXCEPTION) RecordsDaySource.EXCEPTION else RecordsDaySource.SCHEDULED
        return if (isInsideLifeWorkProjection(date)) RecordsDaySource.LIFE_PROJECTION else RecordsDaySource.SCHEDULE_ESTIMATE
    }

    private val sleepHours get() = state.lifeProfile?.averageSleepHours ?: 8.0
    private val sleepFromHealth get() = state.lifeProfile?.sleepSource == SleepSource.HEALTH_SUGGESTED

    /** The whole civil day, ready to draw. */
    fun dayCanvasModel(
        r: DayResolution,
        contributors: List<DayResolution>,
        source: RecordsDaySource,
        nowMs: Double,
        editableAnchors: Set<String> = emptySet(),
    ): RecordsDayCanvasModel {
        val day = date(r.dayKey)
        var shifts = contributors.map { shift ->
            RecordsDayShift(
                anchorDayKey = shift.dayKey,
                segments = shift.segments,
                overtimeSegments = overtimeSegments(shift),
                source = if (shift.dayKey == r.dayKey) source else shiftSource(shift, nowMs),
                isEditable = shift.dayKey in editableAnchors,
            )
        }
        // A past rest or unrecorded day has no hours but is still a real edit anchor.
        if (r.dayKey in editableAnchors && shifts.none { it.anchorDayKey == r.dayKey }) {
            shifts = shifts + RecordsDayShift(r.dayKey, emptyList(), source = source, isEditable = true)
        }
        return RecordsDayCanvasModel.build(
            RecordsDayCanvasModel.Input(
                dayKey = r.dayKey,
                dayStartMs = dayStartMs(day),
                dayEndMs = dayStartMs(day.plusDays(1)),
                source = source,
                shifts = shifts,
                sleepHours = sleepHours,
                sleepFromHealth = sleepFromHealth,
                isToday = day == today(nowMs),
                nowMs = nowMs,
                // Any contributor: a failed overnight tail leaves a hole that is unaccounted for, not free.
                rulesFailed = r.expansionFailed || contributors.any { it.expansionFailed },
            ),
        )
    }

    /** One mapping from a day's appearance to its words, shared by every surface. */
    fun daySource(cell: RecordsDayCell, r: DayResolution): RecordsDaySource {
        if (cell.appearance == RecordsDayAppearance.LOCKED) return RecordsDaySource.LOCKED
        if (cell.isProjection) return RecordsDaySource.LIFE_PROJECTION
        return when (cell.appearance) {
            RecordsDayAppearance.PLANNED -> RecordsDaySource.PLANNED
            RecordsDayAppearance.REST -> RecordsDaySource.REST
            RecordsDayAppearance.UNRECORDED -> RecordsDaySource.UNRECORDED
            RecordsDayAppearance.CORRECTED -> RecordsDaySource.CORRECTED
            RecordsDayAppearance.LOCKED -> RecordsDaySource.LOCKED
            RecordsDayAppearance.RECORDED -> when (r.layer) {
                DayResolutionLayer.OVERRIDE -> RecordsDaySource.CORRECTED
                DayResolutionLayer.CALENDAR_EXCEPTION -> RecordsDaySource.EXCEPTION
                DayResolutionLayer.SCHEDULE -> if (isRecordedDay(r.dayKey)) RecordsDaySource.RECORDED else RecordsDaySource.SCHEDULED
                DayResolutionLayer.NONE -> RecordsDaySource.UNRECORDED
            }
        }
    }

    /**
     * One civil day's page, including the part of the night before that runs
     * into it. A locked day builds a model with nothing real in it at all.
     */
    fun dayCanvas(dayKey: String, nowMs: Double): RecordsDayCanvasModel? {
        val day = runCatching { date(dayKey) }.getOrNull() ?: return null
        val today = today(nowMs)
        if (!RecordsAccess.canRevealDay(day, today, authorized)) {
            return RecordsDayCanvasModel.locked(dayKey, dayStartMs(day), dayStartMs(day.plusDays(1)))
        }
        val resolved = displayDays(day.minusDays(1), day, nowMs)
        val resolution = resolved.firstOrNull { it.dayKey == dayKey } ?: return null
        val previous = resolved.lastOrNull { it.dayKey != dayKey }
        val cell = dayCell(resolution, previous, nowMs, includesLifeProjection = true)
        // Records edits days that have happened; a projected day has no original input to open.
        val editable = if (!authorized) {
            emptySet()
        } else {
            resolved.filter { candidate ->
                val anchor = date(candidate.dayKey)
                !anchor.isAfter(today) &&
                    (contributesHours(candidate, nowMs, includesLifeProjection = false) || !isInsideLifeWorkProjection(anchor))
            }.map { it.dayKey }.toSet()
        }
        return dayCanvasModel(
            resolution, contributingShifts(resolution, previous, nowMs, includesLifeProjection = true),
            daySource(cell, resolution), nowMs, editable,
        )
    }

    companion object {
        private val DAY_KEY = Regex("""^\d{4}-\d{2}-\d{2}$""")
        private const val LIFE_PERIOD_ID = "00000000-0000-0000-0000-00000000L1FE"
        private const val LIFE_SNAPSHOT_ID = "00000000-0000-0000-0000-00000000L1F5"

        /** A year alone stands for 1 July: the middle of the year it names. */
        fun calculationAnchor(date: PartialCivilDate): LocalDate? = LifeDates.anchor(date)
    }
}

/** A day the user authored something on (iOS `RecordDayIndexEntry`). */
data class RecordDayIndexEntry(
    val dayKey: String,
    val observations: List<WorkObservation> = emptyList(),
    val dayOverride: DayOverride? = null,
    val calendarException: CalendarException? = null,
) {
    val hasWorkObservation get() = observations.isNotEmpty()
}

/** Overtime declarations (iOS `RecordsMetrics.declaredOvertimeSegment`). */
object RecordsOvertime {
    /**
     * The overtime an observation declared. The moment the user tapped Save is
     * not the start: the planned end is, from the payload, or for an older
     * payload the day's base schedule.
     */
    fun declaredSegment(observation: WorkObservation, day: DayResolution, avoidingRegularWork: Boolean): ShiftSegment? {
        if (observation.kind != WorkObservationKind.OVERTIME_DECLARED) return null
        val json = observation.valueData?.let(FoundationCompat::base64)?.toString(Charsets.UTF_8) ?: return null
        val end = number(json, "overtimeEndAtMs") ?: return null
        var start = number(json, "plannedEndAtMs") ?: day.baseScheduleSegments.maxOfOrNull { it.endAtMs } ?: return null
        if (avoidingRegularWork) day.segments.maxOfOrNull { it.endAtMs }?.let { start = max(start, it) }
        if (!start.isFinite() || !end.isFinite() || end <= start) return null
        return ShiftSegment(start, end)
    }

    /** A JSON number, as `JSONDecoder` reads a `Double`; a string or null is absent. */
    private fun number(json: String, key: String): Double? = runCatching {
        val value = (Json.parseToJsonElement(json) as? JsonObject)?.get(key) as? JsonPrimitive
        if (value == null || value.isString) null else value.content.toDoubleOrNull()
    }.getOrNull()
}
