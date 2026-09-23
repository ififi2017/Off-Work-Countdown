package com.rainif.doneat.core.domain.session

import com.rainif.doneat.core.domain.records.DayRecordResolver
import com.rainif.doneat.core.domain.records.RecordEditContext
import com.rainif.doneat.core.domain.records.RecordEdits
import com.rainif.doneat.core.domain.records.RecordEntityType
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.records.WorkObservation
import com.rainif.doneat.core.domain.records.WorkObservationKind

/** Applies a session command's records writes to the archive, as one change. */
object SessionRecords {
    /** The entity version `RecordJson` writes for observations. */
    private const val OBSERVATION_SCHEMA_VERSION = 2

    fun apply(state: RecordState, effects: List<SessionRecordEffect>, context: RecordEditContext): RecordState =
        effects.fold(state) { s, effect ->
            when (effect) {
                is SessionRecordEffect.Observation -> recordObservation(s, effect, context)
                is SessionRecordEffect.UpsertOverride -> RecordEdits.upsertOverride(s, effect.override, context)
            }
        }

    /**
     * iOS `RecordCoordinator.recordObservation` after `ensureSeeded`. An
     * erased or repeated event is not written again, and the timer surface's
     * first-seen row is one per civil day.
     */
    fun recordObservation(state: RecordState, o: SessionRecordEffect.Observation, context: RecordEditContext): RecordState {
        val seeded = RecordEdits.ensureSeeded(state, o.hours, context)
        if (seeded.isErased(RecordEntityType.WORK_OBSERVATION, o.eventId)) return seeded
        if (seeded.observations.any { it.eventID == o.eventId }) return seeded
        if (o.kind == WorkObservationKind.TIMER_SURFACE_FIRST_SEEN &&
            seeded.observations.any { it.kind == WorkObservationKind.TIMER_SURFACE_FIRST_SEEN && it.shiftAnchorDate == o.anchorDayKey }
        ) return seeded
        val snapshotID = DayRecordResolver.period(o.anchorDayKey, seeded.periods)
            ?.let { DayRecordResolver.snapshot(o.anchorDayKey, it, seeded.snapshots)?.id } ?: context.newId()
        val row = WorkObservation(
            eventID = o.eventId,
            shiftAnchorDate = o.anchorDayKey,
            occurredAtMs = o.occurredAtMs,
            kind = o.kind,
            valueData = o.valueData,
            scheduleSnapshotID = snapshotID,
            schemaVersion = OBSERVATION_SCHEMA_VERSION,
            timeZoneIdentifier = o.timeZoneIdentifier,
            editedAtMs = o.occurredAtMs,
            editCount = 1,
            editTieBreaker = o.eventId,
        )
        return seeded.copy(observations = seeded.observations + row)
    }
}
