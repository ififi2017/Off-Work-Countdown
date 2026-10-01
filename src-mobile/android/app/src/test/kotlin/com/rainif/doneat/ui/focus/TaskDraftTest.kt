package com.rainif.doneat.ui.focus

import androidx.compose.runtime.saveable.SaverScope
import com.rainif.doneat.core.domain.records.FocusTaskIcon
import org.junit.Assert.assertEquals
import org.junit.Test

class TaskDraftTest {
    @Test fun savedUiStateRestoresAllUnsavedTaskFields() {
        val scope = object : SaverScope { override fun canBeSaved(value: Any) = true }
        val drafts = listOf(
            TaskDraft(),
            TaskDraft("Review 报告", FocusTaskIcon.WRITING, 4, true, "favorite-id"),
            TaskDraft("Existing task", FocusTaskIcon.CODE, 2, false, existingTaskID = "task-id"),
        )
        for (draft in drafts) {
            val saved = with(TaskDraft.Saver) { scope.save(draft) }!!
            assertEquals(draft, TaskDraft.Saver.restore(saved))
        }
    }
}
