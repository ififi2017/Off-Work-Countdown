package com.rainif.doneat.ui.timer

import org.junit.Assert.assertEquals
import org.junit.Test

class OvertimeDialogModeTest {
    private val plannedEnd = 1_800_000_000_000.0

    @Test fun addsBeforeClockOffWithoutOvertime() {
        assertEquals(OvertimeDialogMode.Add, OvertimeDialogs.mode(false, plannedEnd, plannedEnd - 60_000))
    }

    @Test fun adjustsWheneverOvertimeIsSet() {
        assertEquals(OvertimeDialogMode.Adjust, OvertimeDialogs.mode(true, plannedEnd, plannedEnd - 60_000))
        assertEquals(OvertimeDialogMode.Adjust, OvertimeDialogs.mode(true, plannedEnd, plannedEnd + 3_600_000))
    }

    @Test fun logsAfterClockOffWithoutOvertime() {
        assertEquals(OvertimeDialogMode.Log, OvertimeDialogs.mode(false, plannedEnd, plannedEnd))
    }

    @Test fun addsWithoutAPlannedEnd() {
        assertEquals(OvertimeDialogMode.Add, OvertimeDialogs.mode(false, null, plannedEnd))
    }
}
