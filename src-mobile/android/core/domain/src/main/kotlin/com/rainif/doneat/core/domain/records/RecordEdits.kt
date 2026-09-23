package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import com.rainif.doneat.core.domain.schedule.WallClock
import java.time.Instant
import java.util.Locale
import java.util.UUID

/** What a Records day edit writes (iOS `DayRecordWrite`). */
enum class DayRecordWrite { CUSTOM_HOURS, CONFIRMED, LEAVE, REST, MAKEUP, CLEAR }

/**
 * Which layers a write touches. An override wins over an exception, so a
 * rest, makeup or clear write also neutralises a leftover hours override in
 * the same change.
 */
sealed interface DayLayerPlan {
    data class OverrideOnly(val kind: DayOverrideKind) : DayLayerPlan
    data class Exception(val overrideKind: DayOverrideKind, val effect: CalendarEffect, val exceptionCleared: Boolean) : DayLayerPlan

    companion object {
        fun of(write: DayRecordWrite): DayLayerPlan = when (write) {
            DayRecordWrite.CUSTOM_HOURS -> OverrideOnly(DayOverrideKind.CUSTOM_SEGMENTS)
            DayRecordWrite.CONFIRMED -> OverrideOnly(DayOverrideKind.CONFIRMED_AS_SCHEDULED)
            DayRecordWrite.LEAVE -> OverrideOnly(DayOverrideKind.NOT_WORKING)
            DayRecordWrite.REST -> Exception(DayOverrideKind.CLEARED, CalendarEffect.REST, exceptionCleared = false)
            DayRecordWrite.MAKEUP -> Exception(DayOverrideKind.CLEARED, CalendarEffect.WORK, exceptionCleared = false)
            DayRecordWrite.CLEAR -> Exception(DayOverrideKind.CLEARED, CalendarEffect.REST, exceptionCleared = true)
        }
    }
}

/** Everything an edit reads besides the archive. Nothing here reads a clock or a default. */
data class RecordEditContext(
    val nowMs: Double,
    /** The records zone, a Foundation identifier. */
    val recordsTimeZone: String,
    /** Plus access to Records editing; entitlements are decided elsewhere. */
    val canEdit: Boolean,
    val holidays: HolidayCalendar,
    /** Hours to seed the first period with, if the archive has none yet. */
    val currentHours: () -> SnapshotHours,
    val newId: () -> String = { UUID.randomUUID().toString().uppercase(Locale.ROOT) },
)

/**
 * The records edit commands (iOS `RecordsActions` and the coordinator's
 * upserts) as pure functions: each returns the next archive and whether the
 * edit was admitted. `RecordStore.update` runs them, so every layer an edit
 * touches lands in one write or not at all.
 */
object RecordEdits {
    /** Applies a Records day edit. Returns the unchanged archive and false when it is not admitted. */
    fun applyDayWrite(state: RecordState, write: DayRecordWrite, dayKey: String, context: RecordEditContext, startMinutes: Int = 9 * 60, endMinutes: Int = 18 * 60): Pair<RecordState, Boolean> {
        if (!canMutate(dayKey, context)) return state to false
        return when (val plan = DayLayerPlan.of(write)) {
            is DayLayerPlan.OverrideOnly -> when (plan.kind) {
                DayOverrideKind.CUSTOM_SEGMENTS -> saveCustomHours(state, dayKey, startMinutes, endMinutes, context)
                DayOverrideKind.CLEARED -> writeDayLayers(state, dayKey, DayOverrideKind.CLEARED, CalendarEffect.REST, true, context)
                else -> upsertOverride(state, bareOverride(dayKey, plan.kind, context), context) to true
            }
            is DayLayerPlan.Exception -> writeDayLayers(state, dayKey, plan.overrideKind, plan.effect, plan.exceptionCleared, context)
        }
    }

    private fun canMutate(dayKey: String, context: RecordEditContext) =
        context.canEdit && FoundationCompat.canonicalDayKey(dayKey) == dayKey

    private fun bareOverride(dayKey: String, kind: DayOverrideKind, context: RecordEditContext) = DayOverride(
        dayKey, kind, emptyList(), note = null, editedAtMs = 0.0, editCount = 0, editTieBreaker = DayOverrideProjection.ZERO_UUID,
        timeZoneIdentifier = FoundationCompat.timeZoneIdentifier(context.recordsTimeZone) ?: context.recordsTimeZone,
    )

    /**
     * Custom hours keep the planned lunch gap: the snapshot's own segments are
     * clipped or extended to the chosen bounds. An end at or before the start
     * ends on the next day. The first edit seeds the archive in the same change.
     */
    private fun saveCustomHours(state: RecordState, dayKey: String, startMinutes: Int, endMinutes: Int, context: RecordEditContext): Pair<RecordState, Boolean> {
        if (startMinutes !in 0 until 1_440 || endMinutes !in 0 until 1_440) return state to false
        val zone = CivilZone(FoundationCompat.javaZone(context.recordsTimeZone))
        val dayNumber = ExtendedScheduleResolver.dayNumber(dayKey) ?: return state to false
        val start = zone.utcMs(dayNumber, WallClock(startMinutes / 60, startMinutes % 60))
        val sameDayEnd = zone.utcMs(dayNumber, WallClock(endMinutes / 60, endMinutes % 60))
        val end = if (sameDayEnd <= start) zone.addCivilDaysMs(sameDayEnd, 1) else sameDayEnd

        var next = ensureSeeded(state, context.currentHours(), context)
        val period = DayRecordResolver.period(dayKey, next.periods)
        val snapshot = period?.let { DayRecordResolver.snapshot(dayKey, it, next.snapshots) }
        var planned = emptyList<ShiftSegment>()
        if (period != null && snapshot != null) {
            val expansion = RecordHistory.expansion(next, snapshot, period, dayKey, context.holidays)
            if (!expansion.failed) planned = expansion.segments
        }
        if (planned.isEmpty()) planned = listOf(ShiftSegment(start, end))
        val draft = bareOverride(dayKey, DayOverrideKind.CUSTOM_SEGMENTS, context)
            .copy(segments = DayOverrideProjection.applyTimeBounds(planned, start, end))
        next = upsertOverride(next, draft, context)
        return next to true
    }

    private fun writeDayLayers(state: RecordState, dayKey: String, overrideKind: DayOverrideKind, effect: CalendarEffect, exceptionCleared: Boolean, context: RecordEditContext): Pair<RecordState, Boolean> {
        val exception = if (exceptionCleared) {
            state.exceptions.firstOrNull { it.dayKey.startsWith("$dayKey#") && it.origin == CalendarExceptionOrigin.USER }?.copy(isCleared = true)
        } else {
            CalendarException(
                dayKey = "$dayKey#${CalendarExceptionOrigin.USER.raw}", date = dayKey, effect = effect, origin = CalendarExceptionOrigin.USER,
                isCleared = false, regionIdentifier = null, datasetVersion = null, label = null,
                editedAtMs = context.nowMs, editCount = 0, editTieBreaker = context.newId(),
                timeZoneIdentifier = FoundationCompat.timeZoneIdentifier(context.recordsTimeZone) ?: context.recordsTimeZone,
            )
        }
        var next = upsertOverride(state, bareOverride(dayKey, overrideKind, context), context)
        if (exception != null) next = upsertException(next, exception, context)
        return next to true
    }

    // Stamped upserts

    private fun sameContent(a: DayOverride, b: DayOverride) =
        a.copy(editedAtMs = 0.0, editCount = 0, editTieBreaker = "") == b.copy(editedAtMs = 0.0, editCount = 0, editTieBreaker = "")

    private fun sameContent(a: CalendarException, b: CalendarException) =
        a.copy(editedAtMs = 0.0, editCount = 0, editTieBreaker = "") == b.copy(editedAtMs = 0.0, editCount = 0, editTieBreaker = "")

    /** Clears a tombstone because the identity exists again, returning the version it buried. */
    private fun clearErased(state: RecordState, type: RecordEntityType, key: String): Pair<RecordState, Int?> {
        val tombstone = state.erased.firstOrNull { it.entityType == type && it.logicalKey == key } ?: return state to null
        return state.copy(erased = state.erased - tombstone) to tombstone.editCount
    }

    /**
     * Writes an override with a fresh stamp one above the row it replaces;
     * identical business content writes nothing. A day erased earlier revives
     * above its tombstone so every device keeps the revival.
     */
    fun upsertOverride(state: RecordState, draft: DayOverride, context: RecordEditContext): RecordState {
        val current = state.overrides.firstOrNull { it.dayKey == draft.dayKey }
        if (!state.isErased(RecordEntityType.DAY_OVERRIDE, draft.dayKey) && current != null && sameContent(current, draft)) return state
        val (cleared, buried) = clearErased(state, RecordEntityType.DAY_OVERRIDE, draft.dayKey)
        var count = (current?.editCount ?: maxOf(draft.editCount, 0)) + 1
        if (buried != null && count <= buried) count = buried + 1
        val row = draft.copy(editCount = count, editTieBreaker = context.newId(), editedAtMs = context.nowMs)
        val overrides = if (current != null) cleared.overrides.map { if (it === current) row else it } else cleared.overrides + row
        return cleared.copy(overrides = overrides)
    }

    fun upsertException(state: RecordState, draft: CalendarException, context: RecordEditContext): RecordState {
        val current = state.exceptions.firstOrNull { it.dayKey == draft.dayKey }
        if (!state.isErased(RecordEntityType.CALENDAR_EXCEPTION, draft.dayKey) && current != null && sameContent(current, draft)) return state
        val (cleared, buried) = clearErased(state, RecordEntityType.CALENDAR_EXCEPTION, draft.dayKey)
        var count = (current?.editCount ?: maxOf(draft.editCount, 0)) + 1
        if (buried != null && count <= buried) count = buried + 1
        val row = draft.copy(editCount = count, editTieBreaker = context.newId(), editedAtMs = context.nowMs)
        val exceptions = if (current != null) cleared.exceptions.map { if (it === current) row else it } else cleared.exceptions + row
        return cleared.copy(exceptions = exceptions)
    }

    // Periods and snapshots

    /** Creates the first career period and its snapshot, starting today in the records zone. No-op once one exists. */
    fun ensureSeeded(state: RecordState, hours: SnapshotHours, context: RecordEditContext): RecordState {
        if (state.periods.isNotEmpty()) return state
        val zone = FoundationCompat.timeZoneIdentifier(context.recordsTimeZone) ?: context.recordsTimeZone
        val today = FoundationCompat.dayKey(Instant.ofEpochMilli(context.nowMs.toLong()).atZone(FoundationCompat.javaZone(zone)).toLocalDate())
        val period = CareerPeriod(
            id = context.newId(), startsOn = today, endsBefore = null, label = null, timeZoneIdentifier = zone, calendarIdentifier = "gregorian",
            createdAtMs = context.nowMs, editedAtMs = context.nowMs, editCount = 1, editTieBreaker = context.newId(),
        )
        val encoded = ScheduleHoursCodec.encode(hours)
        val snapshot = ScheduleSnapshot(context.newId(), period.id, today, encoded.base64, encoded.fingerprint, context.nowMs, 1, context.newId())
        return state.copy(periods = state.periods + period, snapshots = state.snapshots + snapshot, recordsStartedOn = state.recordsStartedOn ?: today)
    }

    /**
     * Commits hours from [effectiveFrom] in the covering period. Unchanged
     * hours write nothing, and a second save on the same day edits that day's
     * winning snapshot rather than appending a rival row.
     */
    fun commitHours(state: RecordState, hours: SnapshotHours, effectiveFrom: String, context: RecordEditContext): Pair<RecordState, Boolean> {
        // Seeding is kept even when the commit below finds nothing new, as on iOS.
        val seeded = ensureSeeded(state, hours, context)
        val period = DayRecordResolver.period(effectiveFrom, seeded.periods) ?: return seeded to false
        val encoded = ScheduleHoursCodec.encode(hours)
        if (DayRecordResolver.snapshot(effectiveFrom, period, seeded.snapshots)?.fingerprint == encoded.fingerprint) return seeded to false
        val sameDay = seeded.snapshots.filter { it.periodID == period.id && it.effectiveFrom == effectiveFrom }
        val winner = sameDay.maxWithOrNull(compareBy<ScheduleSnapshot> { it.editCount }.thenBy { it.editTieBreaker }.thenBy { it.id })
        val snapshots = if (winner == null) {
            seeded.snapshots + ScheduleSnapshot(context.newId(), period.id, effectiveFrom, encoded.base64, encoded.fingerprint, context.nowMs, 1, context.newId())
        } else {
            // One above every row in that day's slot, not just the winner.
            val edited = winner.copy(
                configurationData = encoded.base64, fingerprint = encoded.fingerprint, editedAtMs = context.nowMs,
                editCount = sameDay.maxOf { it.editCount } + 1, editTieBreaker = context.newId(),
            )
            seeded.snapshots.map { if (it === winner) edited else it }
        }
        return seeded.copy(snapshots = snapshots) to true
    }
}
