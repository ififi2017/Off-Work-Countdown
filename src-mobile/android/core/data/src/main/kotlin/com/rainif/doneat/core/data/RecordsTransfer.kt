package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.*
import com.rainif.doneat.core.domain.schedule.ExtendedSchedule
import com.rainif.doneat.core.domain.schedule.RosterDay
import java.util.UUID

/** What an import would do, worked out on a copy before anything is written. */
sealed interface ImportPreview {
    /** Counts for the review dialog (iOS `previewMessage`). */
    data class Ready(val added: Int, val unchanged: Int, val conflicts: Int, val skippedErased: Int, val rejected: Int) : ImportPreview
    data object TooLarge : ImportPreview
    data object Invalid : ImportPreview
    /** Made by a newer app: never read as an older schema with fields ignored. */
    data object UnsupportedVersion : ImportPreview
}

/**
 * Backups in and out of the records archive (iOS `RecordsActions` export and
 * import, `RecordCoordinator.import`/`exportJSON`, `deleteAllLocalData`).
 *
 * - Export is the schema 6 document, optionally without the Life profile.
 * - Import merges into the archive (same-key conflicts keep the local row,
 *   erased identities are skipped) and is recomputed against the archive as it
 *   stands at commit, inside the store's lock, so a write between preview and
 *   confirm can never be lost; the file is never written half way.
 * - Delete removes the records; the settings, which iOS keeps outside the
 *   archive, stay.
 */
object RecordsTransfer {
    /** The ceiling first-run restore applies too. */
    const val MAX_BYTES = FirstRunRestore.MAX_BYTES

    fun export(state: RecordState, includeLifeProfile: Boolean, nowMs: Double, zone: String): String =
        RecordJson.export(if (includeLifeProfile) state else state.copy(lifeProfile = null), nowMs, zone, "gregorian")

    fun preview(bytes: ByteArray, current: RecordState): ImportPreview {
        if (bytes.size > MAX_BYTES) return ImportPreview.TooLarge
        if (!RecordInputBounds.accepts(bytes)) return ImportPreview.Invalid
        val (_, report) = merge(bytes, current) ?: return classify(bytes)
        return ImportPreview.Ready(
            added = report.inserted.values.sum() + report.adopted.size,
            unchanged = report.unchanged.values.sum(),
            conflicts = report.conflicts.filter { !it.appliedIncoming }.distinctBy { it.entityType to it.logicalKey }.size,
            skippedErased = report.skippedErased.values.sum(),
            rejected = report.rejected.size,
        )
    }

    /**
     * Applies [bytes] to the archive in one write. Returns the number of erased
     * items skipped for the report, or null when nothing was written.
     */
    suspend fun commit(records: RecordStore, bytes: ByteArray): Int? {
        if (bytes.size > MAX_BYTES) return null
        if (!RecordInputBounds.accepts(bytes)) return null
        var skipped: Int? = null
        val result = records.update { current ->
            val merged = merge(bytes, current) ?: return@update current to Unit
            skipped = merged.second.skippedErased.values.sum()
            merged.first to Unit
        }
        return skipped.takeIf { result is WriteResult.Saved }
    }

    /** Removes every record on this device; the settings stay, as iOS keeps them outside its archive. */
    suspend fun deleteRecords(records: RecordStore): Boolean =
        records.update { current -> RecordState(syncedPreferences = current.syncedPreferences) to Unit } is WriteResult.Saved

    private fun merge(bytes: ByteArray, current: RecordState): Pair<RecordState, RecordJson.Report>? = try {
        val document = RecordJson.decode(bytes.toString(Charsets.UTF_8))
        val (merged, report) = RecordJson.apply(document, current, RecordJson.ImportMode.SKIP_ERASED)
        val conflicts = report.conflicts.filter { !it.appliedIncoming }
            .distinctBy { it.entityType to it.logicalKey }.mapNotNull { conflict ->
            if (current.importConflicts.any { it.entityType == conflict.entityType && it.logicalKey == conflict.logicalKey }) null
            else ImportConflictCopy(
                UUID.randomUUID().toString(), conflict.entityType, conflict.logicalKey,
                RecordJson.export(singleRow(conflict.incoming), document.exportedAtMs, document.timeZoneIdentifier, document.calendarIdentifier),
                conflict.localEditCount, conflict.incomingEditCount,
            )
        }
        merged.copy(importConflicts = merged.importConflicts + conflicts) to report
    } catch (_: RecordJson.Error) {
        null
    } catch (_: RuntimeException) {
        null
    }

    internal fun singleRow(value: Any): RecordState = when (value) {
        is CareerPeriod -> RecordState(periods = listOf(value))
        is ScheduleSnapshot -> RecordState(snapshots = listOf(value))
        is CalendarException -> RecordState(exceptions = listOf(value))
        is DayOverride -> RecordState(overrides = listOf(value))
        is WorkObservation -> RecordState(observations = listOf(value))
        is LifeProfile -> RecordState(lifeProfile = value)
        is FocusTask -> RecordState(focusTasks = listOf(value))
        is FocusSession -> RecordState(focusSessions = listOf(value))
        is FocusPlanningConfiguration -> RecordState(focusPlanningConfiguration = value)
        is SyncedPreferences -> RecordState(syncedPreferences = value)
        is ExtendedSchedule -> RecordState(extendedSchedule = value)
        is RosterDay -> RecordState(rosterDays = listOf(value))
        else -> error("unknown record import type")
    }

    private fun classify(bytes: ByteArray): ImportPreview = try {
        RecordJson.decode(bytes.toString(Charsets.UTF_8))
        ImportPreview.Invalid
    } catch (e: RecordJson.Error.UnknownSchemaVersion) {
        // Only a newer schema asks for an update; an older unknown one is simply not a backup.
        if (e.version > RecordJson.SCHEMA_VERSION) ImportPreview.UnsupportedVersion else ImportPreview.Invalid
    } catch (_: Exception) {
        ImportPreview.Invalid
    }
}
