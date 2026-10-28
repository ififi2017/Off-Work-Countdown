package com.rainif.doneat.widget

import com.rainif.doneat.core.domain.records.FocusEndReason
import com.rainif.doneat.core.domain.records.FocusSession
import com.rainif.doneat.core.domain.records.FocusSessionKind
import org.junit.Assert.*
import org.junit.Test

class WidgetFocusActionPolicyTest {
    private val phase = FocusSession("phase", "task", "2026-10-29", 1000.0, 2000.0, null, null,
        1000.0, 0, "tie", FocusSessionKind.FOCUS, "UTC", "2026-10-29", null, FocusEndReason.COMPLETED)

    @Test fun `only the displayed active phase accepts controls`() {
        for (action in listOf("add", "stop")) {
            assertTrue(widgetFocusActionAllowed(true, action, 1000, phase, 1500.0))
            assertFalse(widgetFocusActionAllowed(true, action, 999, phase, 1500.0))
            assertFalse(widgetFocusActionAllowed(true, action, 1000, phase.copy(startedAtMs = 1200.0), 1500.0))
        }
    }
    @Test fun `expired future ended break and revoked controls cannot mutate`() {
        assertFalse(widgetFocusActionAllowed(false, "stop", 1000, phase, 1500.0))
        assertFalse(widgetFocusActionAllowed(true, "stop", 1000, phase, 999.0))
        assertFalse(widgetFocusActionAllowed(true, "stop", 1000, phase, 2000.0))
        assertFalse(widgetFocusActionAllowed(true, "stop", 1000, phase.copy(endedAtMs = 1400.0), 1500.0))
        assertFalse(widgetFocusActionAllowed(true, "add", 1000, phase.copy(kind = FocusSessionKind.SHORT_BREAK), 1500.0))
    }
    @Test fun `missing and unknown action inputs fail closed`() {
        assertFalse(widgetFocusActionAllowed(true, null, 1000, phase, 1500.0))
        assertFalse(widgetFocusActionAllowed(true, "delete", 1000, phase, 1500.0))
        assertFalse(widgetFocusActionAllowed(true, "add", null, phase, 1500.0))
        assertFalse(widgetFocusActionAllowed(true, "stop", 1000, null, 1500.0))
    }
}
