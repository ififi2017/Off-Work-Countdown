package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.RecordJson
import com.rainif.doneat.core.domain.records.RecordState

/** What a backup file would bring onto a new device, before anything is written. */
sealed interface RestorePreview {
    /** [skipped] rows the rules refused; everything else is restored. */
    data class Ready(val state: RecordState, val itemCount: Int, val skipped: Int, val hasSettings: Boolean) : RestorePreview
    /** Not a DoneAt backup, or one this build cannot read. */
    data object Unreadable : RestorePreview
    data object TooLarge : RestorePreview
}

/**
 * Restoring a backup file during first-run setup (plan 01 §6.1): read only,
 * preview, and write only after the user confirms, and only onto an empty
 * archive. Merging into existing records is the import flow's job (T11).
 */
object FirstRunRestore {
    /** The same ceiling the import flow applies. */
    const val MAX_BYTES = 25L * 1024 * 1024

    fun preview(bytes: ByteArray, nowMs: Double): RestorePreview {
        if (bytes.size > MAX_BYTES) return RestorePreview.TooLarge
        // A backup is the schema 1–6 export document itself (what "Export" writes), not the local archive file.
        val (applied, report) = try {
            RecordJson.apply(RecordJson.decode(bytes.toString(Charsets.UTF_8)), RecordState(), RecordJson.ImportMode.SKIP_ERASED)
        } catch (_: RecordJson.Error) {
            return RestorePreview.Unreadable
        } catch (_: RuntimeException) {
            return RestorePreview.Unreadable
        }
        val state = RecordArchive.migrateLegacyAutomaticPeriod(applied, nowMs)
        return RestorePreview.Ready(state, itemCount(state), report.rejected.size, state.syncedPreferences?.isValid == true)
    }

    fun itemCount(s: RecordState) =
        s.periods.size + s.snapshots.size + s.exceptions.size + s.overrides.size + s.observations.size +
            s.focusTasks.size + s.focusSessions.size + s.rosterDays.size +
            listOfNotNull(s.lifeProfile, s.extendedSchedule, s.focusPlanningConfiguration).size

    /**
     * Writes [preview] as the whole archive. Refuses (returns false) when the
     * device already holds records, so a restore can never overwrite them.
     */
    suspend fun commit(records: RecordStore, preview: RestorePreview.Ready): Boolean {
        val result = records.update { current ->
            if (current != RecordState()) current to false else preview.state to true
        }
        return (result as? WriteResult.Saved)?.value == true
    }
}
