package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.DayEditDraft
import com.rainif.doneat.core.domain.records.RecordEditContext
import com.rainif.doneat.core.domain.records.RecordEdits

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
}
