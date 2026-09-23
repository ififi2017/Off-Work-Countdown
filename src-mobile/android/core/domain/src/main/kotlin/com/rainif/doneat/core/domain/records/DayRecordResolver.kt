package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.ShiftSegment

/** Which layer produced a day's conclusion — the source marker every record UI shows. */
enum class DayResolutionLayer(val raw: String) {
    OVERRIDE("override"),
    CALENDAR_EXCEPTION("calendarException"),
    SCHEDULE("schedule"),
    NONE("none"),
}

/** Hours the winning snapshot already expanded through the shared rules. */
data class ScheduleExpansion(
    val isWorkday: Boolean,
    val segments: List<ShiftSegment>,
    val failed: Boolean = false,
    /** A frozen roster assignment can plan a day even without a snapshot. */
    val hasPlannedRoster: Boolean = false,
) {
    companion object {
        val FAILED = ScheduleExpansion(isWorkday = false, segments = emptyList(), failed = true)
        val NONE = ScheduleExpansion(isWorkday = false, segments = emptyList())
    }
}

/** One day's conclusion after the three-layer chain. */
data class DayResolution(
    val dayKey: String,
    val layer: DayResolutionLayer,
    val periodID: String?,
    val snapshotID: String?,
    val isScheduledWorkday: Boolean,
    val segments: List<ShiftSegment>,
    /**
     * The snapshot's plan before an exception or override won. Records income
     * reads this, so leave and one-off edits never rewrite salary history.
     */
    val baseScheduleIsWorkday: Boolean = false,
    val baseScheduleSegments: List<ShiftSegment> = emptyList(),
    val expansionFailed: Boolean = false,
)

/**
 * The winning exception and override for every day an archive mentions,
 * decided once rather than per resolved day. It asks [DayRecordResolver] for
 * the winners, so there is still one definition of which row wins.
 */
class DayRecordLookup(exceptions: List<CalendarException>, overrides: List<DayOverride>) {
    private val exceptions: Map<String, CalendarException> = exceptions
        .groupBy { it.dayKey.substringBefore('#') }
        .mapNotNull { (date, bucket) -> DayRecordResolver.exception(date, bucket)?.let { date to it } }
        .toMap()

    // First row per key wins, as `first(where:)` does, including a cleared one.
    private val overrides: Map<String, DayOverride> = overrides.reversed().associateBy { it.dayKey }

    fun exception(dayKey: String) = exceptions[dayKey]

    /** Null when missing or cleared, so the chain falls through. */
    fun dayOverride(dayKey: String) = overrides[dayKey]?.takeIf { it.kind != DayOverrideKind.CLEARED }
}

/**
 * Read-time resolution (iOS `DayRecordResolver`). The order is fixed: an
 * active day override, else a calendar exception, else the winning schedule
 * snapshot. `cleared` on either layer falls through rather than leaving a
 * layer of its own. Observations are never consulted: they are evidence, not
 * plan. Day keys and period bounds are civil-date labels, so comparing them
 * as strings is comparing dates.
 */
object DayRecordResolver {
    /** The covering period; overlaps pick the later start, then later creation, then id. */
    fun period(dayKey: String, periods: List<CareerPeriod>): CareerPeriod? = periods
        .filter { it.startsOn <= dayKey && (it.endsBefore == null || dayKey < it.endsBefore) }
        .maxWithOrNull(compareBy<CareerPeriod> { it.startsOn }.thenBy { it.createdAtMs }.thenBy { it.id })

    /** The latest snapshot in effect; several on one day rank by edit stamp, then id. */
    fun snapshot(dayKey: String, period: CareerPeriod, snapshots: List<ScheduleSnapshot>): ScheduleSnapshot? {
        val eligible = snapshots.filter { it.periodID == period.id && it.effectiveFrom <= dayKey }
        val latest = eligible.maxOfOrNull { it.effectiveFrom } ?: return null
        return eligible.filter { it.effectiveFrom == latest }
            .maxWithOrNull(compareBy<ScheduleSnapshot> { it.editCount }.thenBy { it.editTieBreaker }.thenBy { it.id })
    }

    /** A user exception beats bundled data; among bundled rows the newer dataset, then the higher edit count. */
    fun exception(dateKey: String, exceptions: List<CalendarException>): CalendarException? {
        val active = exceptions.filter { !it.isCleared && it.dayKey.startsWith("$dateKey#") }
        active.firstOrNull { it.origin == CalendarExceptionOrigin.USER }?.let { return it }
        return active.filter { it.origin == CalendarExceptionOrigin.BUNDLED }.maxWithOrNull { a, b ->
            val left = a.datasetVersion
            val right = b.datasetVersion
            when {
                left != null && right != null && left != right -> left.compareTo(right)
                left == null && right != null -> -1
                left != null && right == null -> 1
                else -> a.editCount.compareTo(b.editCount)
            }
        }
    }

    /** Null when missing or cleared, so the chain falls through. */
    fun dayOverride(dateKey: String, overrides: List<DayOverride>): DayOverride? =
        overrides.firstOrNull { it.dayKey == dateKey }?.takeIf { it.kind != DayOverrideKind.CLEARED }

    fun resolve(
        dayKey: String,
        periods: List<CareerPeriod>,
        snapshots: List<ScheduleSnapshot>,
        exceptions: List<CalendarException>,
        overrides: List<DayOverride>,
        expand: (ScheduleSnapshot) -> ScheduleExpansion,
    ): DayResolution {
        val period = period(dayKey, periods)
        val snapshot = period?.let { snapshot(dayKey, it, snapshots) }
        return resolve(dayKey, period, snapshot, DayRecordLookup(exceptions, overrides), snapshot?.let(expand) ?: ScheduleExpansion.NONE)
    }

    /** The same chain with its lookups already done, for walking a range. */
    fun resolve(
        dayKey: String,
        period: CareerPeriod?,
        snapshot: ScheduleSnapshot?,
        lookup: DayRecordLookup,
        expansion: ScheduleExpansion,
    ): DayResolution {
        val plan = if (snapshot == null && !expansion.hasPlannedRoster) ScheduleExpansion.NONE else expansion
        val empty = DayResolution(dayKey, DayResolutionLayer.NONE, null, null, false, emptyList())
        period ?: return empty
        val baseIsWorkday = snapshot != null && plan.isWorkday
        val baseSegments = if (baseIsWorkday) plan.segments else emptyList()
        val exception = lookup.exception(dayKey)
        val override = lookup.dayOverride(dayKey)
        fun result(layer: DayResolutionLayer, isWorkday: Boolean, segments: List<ShiftSegment>, baseWorkday: Boolean = baseIsWorkday, base: List<ShiftSegment> = baseSegments) =
            DayResolution(dayKey, layer, period.id, snapshot?.id, isWorkday, segments, baseWorkday, base, plan.failed)

        if (plan.failed && override == null && exception == null) {
            return DayResolution(dayKey, DayResolutionLayer.NONE, period.id, snapshot?.id, false, emptyList(), expansionFailed = true)
        }
        when (override?.kind) {
            DayOverrideKind.CUSTOM_SEGMENTS -> return result(DayResolutionLayer.OVERRIDE, true, override.segments)
            DayOverrideKind.NOT_WORKING -> return result(DayResolutionLayer.OVERRIDE, false, emptyList())
            DayOverrideKind.CONFIRMED_AS_SCHEDULED ->
                return result(DayResolutionLayer.OVERRIDE, plan.isWorkday, if (plan.isWorkday) plan.segments else emptyList())
            DayOverrideKind.CLEARED, null -> Unit
        }
        if (exception != null) {
            val isWorkday = exception.effect == CalendarEffect.WORK
            // The exception's base is the raw expansion, whether or not a snapshot supplied it.
            return result(
                DayResolutionLayer.CALENDAR_EXCEPTION, isWorkday, if (isWorkday) plan.segments else emptyList(),
                baseWorkday = plan.isWorkday, base = if (plan.isWorkday) plan.segments else emptyList(),
            )
        }
        if (snapshot == null && !plan.hasPlannedRoster) return empty
        return result(DayResolutionLayer.SCHEDULE, plan.isWorkday, if (plan.isWorkday) plan.segments else emptyList())
    }
}
