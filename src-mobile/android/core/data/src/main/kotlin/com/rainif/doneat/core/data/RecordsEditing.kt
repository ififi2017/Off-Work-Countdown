package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.DayEditDraft
import com.rainif.doneat.core.domain.records.RecordEditContext
import com.rainif.doneat.core.domain.records.RecordEdits
import com.rainif.doneat.core.domain.records.RecordOvertimeState

/**
 * Saves a Records day edit (iOS `RecordsActions.applyDayWrite` and
 * `clearDayOverride`): every layer the edit touches lands in one archive
 * write, or none does.
 */
object RecordsEditing {
    /** True only when the edit was admitted and written; a refused edit leaves the archive as it was. */
    suspend fun save(records: RecordStore, submission: DayEditDraft.Submission, context: RecordEditContext): Boolean {
        var admitted = false
        val result = records.update { state ->
            val (next, ok) = RecordEdits.applyDayWrite(state, submission.write, submission.dayKey, context, submission.startMinutes, submission.endMinutes)
            admitted = ok
            (if (ok) next else state) to Unit
        }
        return admitted && result is WriteResult.Saved
    }

    /** Plan 024 phase 4: writes a day's overtime declaration; true only when it was admitted and written. */
    suspend fun declareOvertime(
        records: RecordStore,
        dayKey: String,
        overtime: RecordOvertimeState,
        context: RecordEditContext,
        capturesObservations: Boolean,
    ): Boolean {
        var admitted = false
        val result = records.update { state ->
            val (next, ok) = RecordEdits.declareOvertime(state, dayKey, overtime, context, capturesObservations)
            admitted = ok
            (if (ok) next else state) to Unit
        }
        return admitted && result is WriteResult.Saved
    }
}
