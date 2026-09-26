package com.rainif.doneat.core.domain.records

import org.junit.Assert.assertEquals
import org.junit.Test

class RecordsFocusHistoryTest {
    private fun session(id: String, reason: FocusEndReason, start: Double = 100_000.0, task: String = "task") =
        FocusSession(id, task, "2026-09-26", start, start + 1_000, start + 1_000, reason,
            0.0, 0, "", FocusSessionKind.FOCUS, "UTC", "2026-09-26", null, FocusEndReason.COMPLETED)

    @Test fun supersededCopyNeedsMatchingSurvivorWithinOneMinute() {
        val copy = session("copy", FocusEndReason.SUPERSEDED_BY_SYNC)
        assertEquals(listOf(copy), RecordsFocusHistory.visible(listOf(copy)))
        assertEquals(listOf("live"), RecordsFocusHistory.visible(listOf(copy, session("live", FocusEndReason.COMPLETED))).map { it.id })
        assertEquals(listOf("copy", "late"), RecordsFocusHistory.visible(listOf(copy, session("late", FocusEndReason.COMPLETED, 160_000.0))).map { it.id })
        assertEquals(listOf("copy", "other"), RecordsFocusHistory.visible(listOf(copy, session("other", FocusEndReason.COMPLETED, task = "other"))).map { it.id })
    }
}
