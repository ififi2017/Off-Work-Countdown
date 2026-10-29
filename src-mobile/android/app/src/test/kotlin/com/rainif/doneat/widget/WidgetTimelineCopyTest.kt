package com.rainif.doneat.widget

import com.rainif.doneat.core.domain.session.TimelineKind
import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetTimelineCopyTest {
    @Test fun shiftBoundaryDetailsStayTheSameWhenTheSnapshotOutlivesTodayOrTheAppReopens() {
        for (detail in listOf("Today's shift", "This month's schedule", "Next month's schedule", "")) {
            assertEquals("", widgetTimelineDetail(TimelineKind.SHIFT_START, false, detail, "Overtime"))
            assertEquals("", widgetTimelineDetail(TimelineKind.SHIFT_END, false, detail, "Overtime"))
            assertEquals("Overtime", widgetTimelineDetail(TimelineKind.SHIFT_END, true, detail, "Overtime"))
        }
    }

    @Test fun breakFocusAndReminderDetailsArePreservedAndOvertimeUsesTheAppLanguage() {
        for (kind in listOf(TimelineKind.LUNCH_START, TimelineKind.LUNCH_END, TimelineKind.HEALTH,
                TimelineKind.MILESTONE, TimelineKind.FOCUS, TimelineKind.FOCUS_BREAK)) {
            assertEquals("12:00–13:00", widgetTimelineDetail(kind, false, "12:00–13:00", "加班"))
        }
        assertEquals("加班", widgetTimelineDetail(TimelineKind.SHIFT_END, true, "Today's shift", "加班"))
    }
}
