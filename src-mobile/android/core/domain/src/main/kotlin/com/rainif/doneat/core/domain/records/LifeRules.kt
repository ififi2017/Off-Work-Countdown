package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.ShiftSegment
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.max
import kotlin.math.min

/**
 * The Life scale's rules (iOS `LifeStageCalculator`, `LifeViewCalculator` and
 * the profile write in `RecordCoordinator.updateLifeProfile`). Everything here
 * is a projection read from the profile and the expanded schedule; nothing is
 * written back except the profile itself.
 *
 * Instants are Unix milliseconds; civil dates become the start of their day
 * in the records zone.
 */
object LifeDates {
    /** A year alone stands for 1 July, the middle of the year it names; never 1 January. */
    fun anchor(date: PartialCivilDate): LocalDate? = when (date.precision) {
        CivilDatePrecision.YEAR -> runCatching { LocalDate.of(date.year, 7, 1) }.getOrNull()
        CivilDatePrecision.DAY -> {
            val month = date.month
            val day = date.day
            if (month == null || day == null) null else runCatching { LocalDate.of(date.year, month, day) }.getOrNull()
        }
    }

    fun yearOnly(year: Int) = PartialCivilDate(year, null, null, CivilDatePrecision.YEAR)

    /** A real calendar day, or null: 31 February is not a date. */
    fun exact(year: Int, month: Int, day: Int): PartialCivilDate? {
        if (month !in 1..12 || day !in 1..31) return null
        runCatching { LocalDate.of(year, month, day) }.getOrNull() ?: return null
        return PartialCivilDate(year, month, day, CivilDatePrecision.DAY)
    }

    fun ms(day: LocalDate, zone: ZoneId) = day.atStartOfDay(zone).toInstant().toEpochMilli().toDouble()

    fun anchorMs(date: PartialCivilDate?, zone: ZoneId) = date?.let(::anchor)?.let { ms(it, zone) }

    fun LifeSalary.isValid() = amount.isFinite() && amount > 0

    fun LifeIncomeDecline.isValid() = startsAtAge in 0..120 && retirementRatio.isFinite() && retirementRatio in 0.0..1.0

    /** The suggestion shown for an empty field: school at six, work at twenty-two. */
    fun suggestedSchoolYear(profile: LifeProfile?) = (profile?.bornOn?.year ?: profile?.birthYear)?.plus(6)
    fun suggestedWorkYear(profile: LifeProfile?) = (profile?.bornOn?.year ?: profile?.birthYear)?.plus(22)
}

enum class LifeStageKind { CHILDHOOD, STUDY, WORK, RETIREMENT, UNSET }

enum class LifeWorkPeriod(val raw: String) { ELAPSED("elapsed"), FUTURE("future") }

/** One stage of a life. It keeps its configured identity while the live now-split moves. */
data class LifeStageSpan(
    val kind: LifeStageKind,
    val startMs: Double?,
    val endMs: Double?,
    val startPrecision: CivilDatePrecision?,
    val endPrecision: CivilDatePrecision?,
    val workPeriod: LifeWorkPeriod? = null,
    private val sourceID: String = listOf(kind.name.lowercase(), startMs?.toLong()?.toString() ?: "open", endMs?.toLong()?.toString() ?: "open").joinToString("."),
) {
    val id get() = workPeriod?.let { "$sourceID.${it.raw}" } ?: sourceID
}

data class LifeCanvasBucket(
    val index: Int,
    val startMs: Double,
    val endMs: Double,
    val kind: LifeStageKind,
    val stageID: String,
    val isCurrent: Boolean,
    val isFuture: Boolean,
)

object LifeStageCalculator {
    /** Presentation only: splits a career at now without creating records or moving retirement. */
    fun canvasStages(stages: List<LifeStageSpan>, nowMs: Double): List<LifeStageSpan> = stages.flatMap { stage ->
        val start = stage.startMs
        if (stage.kind != LifeStageKind.WORK || start == null) return@flatMap listOf(stage)
        val result = mutableListOf<LifeStageSpan>()
        if (start < nowMs) {
            val end = min(stage.endMs ?: nowMs, nowMs)
            result += stage.copy(endMs = end, workPeriod = LifeWorkPeriod.ELAPSED, endPrecision = if (end == nowMs) CivilDatePrecision.DAY else stage.endPrecision)
        }
        val end = stage.endMs
        if (end != null && end > nowMs) {
            val futureStart = max(start, nowMs)
            result += stage.copy(startMs = futureStart, workPeriod = LifeWorkPeriod.FUTURE, startPrecision = if (futureStart == nowMs) CivilDatePrecision.DAY else stage.startPrecision)
        }
        result.ifEmpty { listOf(stage) }
    }

    fun stages(profile: LifeProfile, zone: ZoneId, nowMs: Double): List<LifeStageSpan> {
        val p = RecordJson.migrateLegacyFields(profile)
        val born = LifeDates.anchorMs(p.bornOn, zone)
        val school = LifeDates.anchorMs(p.schoolStartedOn, zone)
        val work = LifeDates.anchorMs(p.workStartedPartial, zone) ?: p.workStartedOn?.let { runCatching { LifeDates.ms(LocalDate.parse(it), zone) }.getOrNull() }
        val retire = LifeDates.anchorMs(p.retirementOn, zone)
        val early = listOf(
            LifeStageSpan(LifeStageKind.CHILDHOOD, born, school ?: work, p.bornOn?.precision, p.schoolStartedOn?.precision ?: p.workStartedPartial?.precision),
            LifeStageSpan(LifeStageKind.STUDY, school, work, p.schoolStartedOn?.precision, p.workStartedPartial?.precision),
        )
        val workStages = if (p.workHistoryMode == LifeWorkHistoryMode.DETAILED) {
            detailedWorkStages(p, retire, nowMs, zone)
        } else {
            listOf(LifeStageSpan(LifeStageKind.WORK, work, retire, p.workStartedPartial?.precision, p.retirementOn?.precision))
        }
        return early + workStages + LifeStageSpan(LifeStageKind.RETIREMENT, retire, null, p.retirementOn?.precision, null)
    }

    private fun detailedWorkStages(p: LifeProfile, retirement: Double?, nowMs: Double, zone: ZoneId): List<LifeStageSpan> {
        val stages = p.employmentPeriods.mapNotNull { period ->
            val start = LifeDates.anchorMs(period.startsOn, zone) ?: return@mapNotNull null
            val end = LifeDates.anchorMs(period.endsOn, zone) ?: retirement
            if (end != null && end <= start) return@mapNotNull null
            LifeStageSpan(
                LifeStageKind.WORK, start, end, period.startsOn.precision, period.endsOn?.precision ?: p.retirementOn?.precision,
                sourceID = "employment.${period.id.lowercase()}",
            )
        }.toMutableList()
        if (p.employmentPeriods.none { it.endsOn == null } && p.roughCurrentSalary?.let { with(LifeDates) { it.isValid() } } == true) {
            val start = LifeDates.ms(java.time.Instant.ofEpochMilli(nowMs.toLong()).atZone(zone).toLocalDate(), zone)
            if (retirement == null || retirement > start) {
                stages += LifeStageSpan(LifeStageKind.WORK, start, retirement, CivilDatePrecision.DAY, p.retirementOn?.precision, sourceID = "employment.current-salary")
            }
        }
        return stages.sortedBy { it.startMs ?: Double.NEGATIVE_INFINITY }
    }

    /** Birth to retirement; once retirement has begun, the retired years so far are included. No invented death date. */
    fun timelineBounds(stages: List<LifeStageSpan>, nowMs: Double): Pair<Double, Double>? {
        val origin = stages.mapNotNull { it.startMs }.minOrNull() ?: return null
        val retire = stages.firstOrNull { it.kind == LifeStageKind.RETIREMENT }?.startMs
        val configuredEnd = retire ?: stages.mapNotNull { it.endMs }.maxOrNull() ?: nowMs
        val end = max(configuredEnd, nowMs)
        return if (end > origin) origin to end else null
    }

    fun buckets(stages: List<LifeStageSpan>, fromMs: Double, toMs: Double, count: Int, nowMs: Double): List<LifeCanvasBucket> {
        if (count <= 0 || toMs <= fromMs) return emptyList()
        val span = toMs - fromMs
        return (0 until count).map { index ->
            val start = fromMs + span * index / count
            val end = fromMs + span * (index + 1) / count
            val mid = start + (end - start) / 2
            // The current bucket samples just before now, so tapping the present selects the elapsed half.
            val isCurrent = nowMs >= start && (nowMs < end || (index == count - 1 && nowMs == end))
            val sample = if (isCurrent && nowMs > fromMs) nowMs - 1 else mid
            val stage = stageAt(sample, stages)
            LifeCanvasBucket(index, start, end, stage?.kind ?: LifeStageKind.UNSET, stage?.id ?: "unset", isCurrent, !isCurrent && mid > nowMs)
        }
    }

    fun kindAt(atMs: Double, stages: List<LifeStageSpan>) = stageAt(atMs, stages)?.kind ?: LifeStageKind.UNSET

    fun stageAt(atMs: Double, stages: List<LifeStageSpan>) = stages.firstOrNull { contains(it, atMs, stages) }

    fun progress(fromMs: Double, toMs: Double, atMs: Double): Double {
        val duration = toMs - fromMs
        return if (duration <= 0) 0.0 else ((atMs - fromMs) / duration).coerceIn(0.0, 1.0)
    }

    /** An open stage stops at the next stage that starts, so childhood without school never paints over work. */
    private fun contains(stage: LifeStageSpan, atMs: Double, stages: List<LifeStageSpan>): Boolean {
        val start = stage.startMs ?: return false
        val end = stage.endMs ?: stages.mapNotNull { it.startMs }.filter { it > start }.minOrNull()
        return if (end != null) atMs >= start && atMs < end else atMs >= start
    }
}

enum class LifeWeekKind {
    CHILDHOOD, STUDY, WORK_ESTIMATED, WORK_PROJECTED, WORK_OVERRIDE, RETIREMENT, NONE;

    val isWork get() = this == WORK_ESTIMATED || this == WORK_PROJECTED || this == WORK_OVERRIDE
    val isPast get() = this == WORK_ESTIMATED || this == WORK_OVERRIDE || this == CHILDHOOD || this == STUDY
}

data class LifeWeekCell(val year: Int, val weekIndex: Int, val startMs: Double, val kind: LifeWeekKind, val outsidePeriodTimeZone: Boolean)

/**
 * One career day after the rules and the three-layer chain. An absent day is a
 * career gap; a present day without segments is covered rest or leave.
 */
data class LifeScheduleDay(
    val periodID: String,
    val dayKey: String,
    val anchorMs: Double,
    val segments: List<ShiftSegment>,
    /** Overtime actually declared: only ever a record, never forecast forward. */
    val overtimeSegments: List<ShiftSegment> = emptyList(),
    val isOverride: Boolean,
)

data class LifeViewModel(
    val cells: List<LifeWeekCell>,
    val workShare: Double,
    val ownAwakeShare: Double,
    val income: com.rainif.doneat.core.domain.summary.SummaryRules.LifetimeIncome? = null,
    /** Birth to retirement in the six categories every records surface uses; a projection only. */
    val allocation: TimeAllocationShare = TimeAllocationShare.ZERO,
) {
    val workedWeeks get() = cells.count { it.kind.isWork && it.kind.isPast }
    val remainingWeeks get() = cells.count { it.kind == LifeWeekKind.WORK_PROJECTED }
}

object LifeViewCalculator {
    private data class Interval(val startMs: Double, val endMs: Double)

    fun build(profile: LifeProfile, scheduleDays: List<LifeScheduleDay>, outsideZoneDays: Set<String>, nowMs: Double, zone: ZoneId): LifeViewModel {
        val p = RecordJson.migrateLegacyFields(profile)
        val lifeStartDay = p.bornOn?.let(LifeDates::anchor)
        val lifeEndDay = p.retirementOn?.let(LifeDates::anchor)
        if (lifeStartDay == null || lifeEndDay == null || !lifeEndDay.isAfter(lifeStartDay)) return LifeViewModel(emptyList(), 0.0, 0.0)
        val lifeStart = LifeDates.ms(lifeStartDay, zone)
        val lifeEnd = LifeDates.ms(lifeEndDay, zone)
        val schoolStart = LifeDates.anchorMs(p.schoolStartedOn, zone) ?: LifeDates.ms(lifeStartDay.plusYears(6), zone)
        val workStart = LifeDates.anchorMs(p.workStartedPartial, zone)
            ?: p.workStartedOn?.let { runCatching { LifeDates.ms(LocalDate.parse(it), zone) }.getOrNull() }
            ?: LifeDates.ms(lifeStartDay.plusYears(22), zone)
        val coverage = detailedEmploymentCoverage(p, nowMs, lifeStart, lifeEnd, lifeEndDay, zone)
        val work = limited(merged(scheduleDays.flatMap { it.segments }, lifeStart, lifeEnd), coverage)
        val overrides = limited(merged(scheduleDays.filter { it.isOverride }.flatMap { it.segments }, lifeStart, lifeEnd), coverage)
        val outsideAnchors = scheduleDays.filter { it.dayKey in outsideZoneDays }.map { it.anchorMs }.sorted()

        val cells = mutableListOf<LifeWeekCell>()
        var cursorDay: LocalDate = lifeStartDay
        var weekIndex = 0
        var workIndex = 0
        var overrideIndex = 0
        var outsideIndex = 0
        while (cursorDay.isBefore(lifeEndDay)) {
            val cursor = LifeDates.ms(cursorDay, zone)
            val cellEndDay = minOf(cursorDay.plusDays(7), lifeEndDay)
            val cellEnd = LifeDates.ms(cellEndDay, zone)
            val (hasWork, nextWork) = intersects(work, cursor, cellEnd, workIndex)
            workIndex = nextWork
            val kind = if (hasWork) {
                val firstStartsInFuture = workIndex < work.size && work[workIndex].startMs >= nowMs
                val (hasOverride, nextOverride) = intersects(overrides, cursor, cellEnd, overrideIndex)
                overrideIndex = nextOverride
                when {
                    firstStartsInFuture -> LifeWeekKind.WORK_PROJECTED
                    hasOverride && cursor <= nowMs -> LifeWeekKind.WORK_OVERRIDE
                    else -> LifeWeekKind.WORK_ESTIMATED
                }
            } else if (cellEnd <= workStart) {
                if (cellEnd <= schoolStart) LifeWeekKind.CHILDHOOD else LifeWeekKind.STUDY
            } else {
                // No expanded work here is a career gap, covered rest or leave: never implicit work.
                LifeWeekKind.NONE
            }
            while (outsideIndex < outsideAnchors.size && outsideAnchors[outsideIndex] < cursor) outsideIndex++
            val outside = outsideIndex < outsideAnchors.size && outsideAnchors[outsideIndex] < cellEnd
            cells += LifeWeekCell(cursorDay.year, weekIndex, cursor, kind, outside)
            cursorDay = cellEndDay
            weekIndex++
        }
        val total = lifeEnd - lifeStart
        val workMs = work.sumOf { it.endMs - it.startMs }
        val overtimeMs = subtracting(limited(merged(scheduleDays.flatMap { it.overtimeSegments }, lifeStart, lifeEnd), coverage), work)
        val workShare = if (total > 0) ((workMs + overtimeMs) / total).coerceIn(0.0, 1.0) else 0.0
        val sleepHours = (p.averageSleepHours ?: p.averageSleepMinutes?.let { it / 60.0 } ?: 8.0).coerceIn(0.0, 24.0)
        val sleepMs = total * sleepHours / 24
        val ownAwakeShare = if (total > 0) ((total - sleepMs - workMs - overtimeMs) / total).coerceIn(0.0, 1.0) else 0.0
        val breakMs = limited(merged(scheduleDays.flatMap { TimeAllocationShare.gaps(it.segments) }, lifeStart, lifeEnd), coverage).sumOf { it.endMs - it.startMs }
        return LifeViewModel(cells, workShare, ownAwakeShare, allocation = allocation(total, workMs, overtimeMs, breakMs, sleepHours))
    }

    /** Recorded overtime keeps its own slice; sleep is the profile's average; the rest is the person's own. */
    private fun allocation(total: Double, workMs: Double, overtimeMs: Double, breakMs: Double, sleepHours: Double): TimeAllocationShare {
        if (total <= 0) return TimeAllocationShare.ZERO
        val work = min(total, max(0.0, workMs))
        val overtime = min(total - work, max(0.0, overtimeMs))
        val breaks = min(total - work - overtime, max(0.0, breakMs))
        val sleep = min(total - work - overtime - breaks, total * sleepHours / 24)
        val free = max(0.0, total - work - overtime - breaks - sleep)
        return TimeAllocationShare(work.toLong(), overtime.toLong(), breaks.toLong(), sleep.toLong(), free.toLong(), 0, total.toLong())
    }

    /** The same minute is never counted as both regular work and overtime. */
    private fun subtracting(intervals: List<Interval>, taken: List<Interval>) = intervals.sumOf { interval ->
        val overlap = taken.sumOf { max(0.0, min(interval.endMs, it.endMs) - max(interval.startMs, it.startMs)) }
        max(0.0, interval.endMs - interval.startMs - overlap)
    }

    /** Detailed histories count schedule time only inside a supplied job; the gaps stay the person's own. */
    private fun detailedEmploymentCoverage(p: LifeProfile, nowMs: Double, lifeStart: Double, lifeEnd: Double, lifeEndDay: LocalDate, zone: ZoneId): List<Interval>? {
        if (p.workHistoryMode != LifeWorkHistoryMode.DETAILED) return null
        val intervals = p.employmentPeriods.mapNotNull { period ->
            val start = LifeDates.anchorMs(period.startsOn, zone) ?: return@mapNotNull null
            val end = LifeDates.anchorMs(period.endsOn, zone) ?: LifeDates.ms(lifeEndDay, zone)
            clipped(start, end, lifeStart, lifeEnd)
        }.toMutableList()
        if (p.employmentPeriods.none { it.endsOn == null } && p.roughCurrentSalary?.let { with(LifeDates) { it.isValid() } } == true) {
            val today = LifeDates.ms(java.time.Instant.ofEpochMilli(nowMs.toLong()).atZone(zone).toLocalDate(), zone)
            clipped(today, lifeEnd, lifeStart, lifeEnd)?.let { intervals += it }
        }
        return merge(intervals)
    }

    private fun clipped(start: Double, end: Double, lifeStart: Double, lifeEnd: Double): Interval? {
        val lower = max(start, lifeStart)
        val upper = min(end, lifeEnd)
        return if (upper > lower) Interval(lower, upper) else null
    }

    private fun limited(intervals: List<Interval>, coverage: List<Interval>?): List<Interval> {
        coverage ?: return intervals
        return merge(
            intervals.flatMap { interval ->
                coverage.mapNotNull { job ->
                    val start = max(interval.startMs, job.startMs)
                    val end = min(interval.endMs, job.endMs)
                    if (end > start) Interval(start, end) else null
                }
            },
        )
    }

    private fun merge(intervals: List<Interval>): List<Interval> {
        val merged = mutableListOf<Interval>()
        for (interval in intervals.sortedWith(compareBy<Interval> { it.startMs }.thenBy { it.endMs })) {
            val last = merged.lastOrNull()
            if (last != null && interval.startMs <= last.endMs) merged[merged.lastIndex] = Interval(last.startMs, max(last.endMs, interval.endMs)) else merged += interval
        }
        return merged
    }

    /** A union, so an overnight segment and a correction never count the same time twice. */
    private fun merged(segments: List<ShiftSegment>, lower: Double, upper: Double) = merge(
        segments.mapNotNull {
            val start = max(lower, it.startAtMs)
            val end = min(upper, it.endAtMs)
            if (end > start) Interval(start, end) else null
        },
    )

    /** Advances a sorted stream monotonically with the week cursor; a life never rescans every segment per week. */
    private fun intersects(intervals: List<Interval>, lower: Double, upper: Double, startingAt: Int): Pair<Boolean, Int> {
        var index = startingAt
        while (index < intervals.size && intervals[index].endMs <= lower) index++
        return (index < intervals.size && intervals[index].startMs < upper) to index
    }
}

/** Writing the one Life profile (iOS `LifeSummaryModel.applyProfileEdit` and `RecordCoordinator.updateLifeProfile`). */
object LifeProfiles {
    /** A blank profile for a first edit. */
    fun blank(nowMs: Double, newId: () -> String) = LifeProfile(
        LifeProfile.PROFILE_ID, null, null, null, null, false, null, null, null, null, null, null, null,
        LifeWorkHistoryMode.ROUGH, null, emptyList(), null, nowMs, 0, newId(),
    )

    /**
     * Applies [change] to the latest profile and stamps it one edit above the
     * one it replaces; identical business content writes nothing. Manual
     * sleep keeps its timestamp unless its value changed. A profile erased
     * earlier revives above its tombstone.
     */
    fun edit(state: RecordState, nowMs: Double, newId: () -> String, change: (LifeProfile) -> LifeProfile): RecordState {
        val previous = state.lifeProfile
        var next = change(previous ?: blank(nowMs, newId))
        if (next.sleepSource == SleepSource.MANUAL) {
            val unchanged = previous?.sleepSource == SleepSource.MANUAL &&
                previous.averageSleepMinutes == next.averageSleepMinutes && previous.averageSleepHours == next.averageSleepHours
            next = next.copy(sleepSourceUpdatedAtMs = if (unchanged) previous?.sleepSourceUpdatedAtMs else nowMs)
        }
        next = RecordJson.migrateLegacyFields(next)
        val key = LifeProfile.PROFILE_ID
        val erased = state.erased.firstOrNull { it.entityType == RecordEntityType.LIFE_PROFILE && it.logicalKey == key }
        if (erased == null && previous != null && sameContent(previous, next)) return state
        var count = (previous?.editCount ?: max(next.editCount, 0)) + 1
        if (erased != null && count <= erased.editCount) count = erased.editCount + 1
        return state.copy(
            lifeProfile = next.copy(editCount = count, editTieBreaker = newId(), editedAtMs = nowMs),
            erased = if (erased != null) state.erased - erased else state.erased,
        )
    }

    private fun sameContent(a: LifeProfile, b: LifeProfile) =
        a.copy(editedAtMs = 0.0, editCount = 0, editTieBreaker = "") == b.copy(editedAtMs = 0.0, editCount = 0, editTieBreaker = "")
}
