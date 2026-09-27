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
    val recordDayIndex: List<RecordDayIndexEntry> by lazy { indexedRecords() }

    fun indexedRecords(checkActive: () -> Unit = {}): List<RecordDayIndexEntry> {
        val entries = linkedMapOf<String, RecordDayIndexEntry>()
        fun entry(key: String) = entries.getOrPut(key) { RecordDayIndexEntry(key) }
        for (o in state.observations) {
            checkActive()
            if (o.kind == WorkObservationKind.TIMER_SURFACE_FIRST_SEEN) continue
            entries[o.shiftAnchorDate] = entry(o.shiftAnchorDate).let { it.copy(observations = it.observations + o) }
        }
        for (o in state.overrides) {
            checkActive()
            if (o.kind == DayOverrideKind.CLEARED) continue
            entries[o.dayKey] = entry(o.dayKey).copy(dayOverride = o)
        }
        for (e in state.exceptions) {
            checkActive()
            if (e.origin != CalendarExceptionOrigin.USER || e.isCleared) continue
            val key = e.dayKey.substringBefore('#')
            if (!DAY_KEY.matches(key)) continue
            entries[key] = entry(key).copy(calendarException = e)
        }
        return entries.values.map { checkActive(); it.copy(observations = it.observations.sortedBy { o -> o.occurredAtMs }) }.sortedByDescending { it.dayKey }
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
    fun resolvedDays(from: LocalDate, through: LocalDate, checkActive: () -> Unit = {}): List<DayResolution> =
        walk(from, through, state.periods, state.snapshots, checkActive)

    /**
     * Records month, week and year days: the archive, plus the life profile's
     * in-memory history for the years before it. Estimated days never become
     * durable rows.
     */
    fun displayDays(from: LocalDate, through: LocalDate, nowMs: Double, checkActive: () -> Unit = {}): List<DayResolution> {
        val bounds = lifeWorkProjectionBounds ?: return resolvedDays(from, through, checkActive)
        val (periods, snapshots) = lifeScheduleArchive(bounds.first, nowMs)
        return walk(from, through, periods, snapshots, checkActive)
    }

    private fun walk(from: LocalDate, through: LocalDate, periods: List<CareerPeriod>, snapshots: List<ScheduleSnapshot>, checkActive: () -> Unit): List<DayResolution> {
        if (through.isBefore(from)) return emptyList()
        val fromKey = FoundationCompat.dayKey(from)
        val throughKey = FoundationCompat.dayKey(through)
        val expansions = expansions(fromKey, throughKey, periods, snapshots, checkActive)
        val lookup = DayRecordLookup(state.exceptions, state.overrides)
        val result = ArrayList<DayResolution>()
        var day = from
        while (!day.isAfter(through)) {
            checkActive()
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
    private fun expansions(fromKey: String, throughKey: String, periods: List<CareerPeriod>, snapshots: List<ScheduleSnapshot>, checkActive: () -> Unit): Expansions {
        val table = Expansions()
        for (snapshot in snapshots) {
            checkActive()
            val period = periods.firstOrNull { it.id == snapshot.periodID } ?: continue
            if (period.startsOn > throughKey || (period.endsBefore != null && period.endsBefore <= fromKey)) continue
            if (snapshot.effectiveFrom > throughKey || snapshot.id in table.bySnapshot || snapshot.id in table.failures) continue
            val hours = RecordHistory.expandableHours(state, snapshot, holidays)
            if (hours == null) {
                table.failures += snapshot.id
                continue
            }
            table.bySnapshot[snapshot.id] = expand(hours, fromKey, throughKey, period.timeZoneIdentifier, checkActive)
                // The first of two duplicate civil keys (a date-line change) wins.
                .groupBy { it.dayKey }.mapValues { (_, days) -> ScheduleExpansion(days.first().isWorkday, days.first().segments) }
        }
        // Frozen roster rows plan days before any snapshot reached them.
        val plan = ExtendedSchedulePlan.historical(state.rosterDays) ?: return table
        val rosterHours = ScheduleHours("00:00", "00:01", emptyList(), WorkSchedule(ScheduleMode.OFF), null, 0, plan)
        for (key in plan.frozenShiftTypes.keys) {
            checkActive()
            if (key < fromKey || key > throughKey) continue
            val period = DayRecordResolver.period(key, periods) ?: continue
            if (DayRecordResolver.snapshot(key, period, snapshots) != null) continue
            val day = expand(rosterHours, key, key, period.timeZoneIdentifier, checkActive).firstOrNull() ?: continue
            table.withoutSnapshot[key] = ScheduleExpansion(day.isWorkday, day.segments, hasPlannedRoster = true)
        }
        return table
    }

    private fun expand(hours: ScheduleHours, fromKey: String, throughKey: String, zoneIdentifier: String, checkActive: () -> Unit) = run {
        val zone = FoundationCompat.javaZone(zoneIdentifier)
        val civil = CivilZone(zone)
        val from = ExtendedScheduleResolver.dayNumber(fromKey) ?: return@run emptyList()
        val through = ExtendedScheduleResolver.dayNumber(throughKey) ?: return@run emptyList()
        ScheduleRules.expandScheduleRange(hours, civil.utcMs(from, WallClock.MIDNIGHT), civil.utcMs(through, WallClock.MIDNIGHT), zone, checkActive)
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
    fun lifeModel(nowMs: Double, configuredMonthly: Double?, checkActive: () -> Unit = {}): LifeViewModel? {
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
            walk(workStart, lifeEnd.minusDays(1), periods, snapshots, checkActive).mapNotNull { r ->
                checkActive()
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
        return LifeViewCalculator.build(profile, days, outside, nowMs, zone, checkActive).copy(income = lifeIncome(profile, nowMs, configuredMonthly))
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

    fun dayCell(resolution: DayResolution, previous: DayResolution?, nowMs: Double, includesLifeProjection: Boolean = false): RecordsDayCell {
        val today = today(nowMs)
        val date = date(resolution.dayKey)
        val revealed = RecordsAccess.canRevealDay(date, today, authorized)
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
        // Observed, corrected and elapsed saved-schedule days count; a day only
        // receiving hours after midnight counts for its time, never as a workday.
        val byKey = days.associateBy { it.dayKey }
        val counted = days.filter { contributesHours(it, nowMs, includesLifeProjection = false) }.map { it.dayKey }.toSet()
        val shares = cells.mapNotNull { cell ->
            val day = byKey[cell.dayKey] ?: return@mapNotNull null
            val contributors = listOfNotNull(previousDay(day, byKey), day).filter { it.dayKey in counted }
            if (contributors.isEmpty()) return@mapNotNull null
            val allocation = dayAllocation(day, contributors, nowMs)
            // A neighbouring record alone does not make this a covered day.
            if (day.dayKey !in recordedKeys && allocation.workMs <= 0 && allocation.overtimeMs <= 0 && allocation.breakMs <= 0) return@mapNotNull null
            allocation
        }
        val combined = TimeAllocationShare.combining(shares)
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
            if (actualKind == null && !isForecast) return@mapNotNull null
            SummaryRules.RecordsDay(
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
