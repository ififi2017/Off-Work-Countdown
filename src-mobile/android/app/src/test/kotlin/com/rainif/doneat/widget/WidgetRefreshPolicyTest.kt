package com.rainif.doneat.widget

import com.rainif.doneat.core.domain.widget.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class WidgetRefreshPolicyTest {
    private val now = Instant.parse("2026-10-28T09:00:15Z").toEpochMilli()
    private fun suite(zone: String = "UTC", focus: WidgetFocusPayload = WidgetFocusPayload(WidgetAccess.LOCKED),
                      calendar: WidgetCalendarPayload = WidgetCalendarPayload(zone, 1, WidgetCalendarScheduleKind.WEEKLY)) = WidgetSuiteSnapshot(
        generatedAtMs = now, locale = "en", timeZoneIdentifier = zone, calendar = calendar,
        summary = WidgetSummaryPayload(WidgetAccess.LOCKED), life = WidgetLifePayload(WidgetAccess.LOCKED),
        holiday = WidgetHolidayPayload(WidgetAccess.LOCKED, weekendStartMs = now + 3_600_000), focus = focus)
    private fun countdown() = WidgetEntry(now, now + 3_600_000, WidgetPhase.WORKING, "widgetWorking",
        WidgetCountdownKind.WORK_REMAINING, 3_600_000, null, 3_600_000, 0.0, now + 3_600_000)

    @Test fun `suite cache never increases legacy countdown refresh frequency`() {
        assertEquals(now + 15 * 60_000, widgetNextRefreshAt(countdown(), suite(), emptySet(), now))
        assertEquals(now + 15 * 60_000, widgetNextRefreshAt(countdown(), suite(), setOf(DoneAtWidgetKind.BIG, DoneAtWidgetKind.RING), now))
    }
    @Test fun `suite file alone never schedules an alarm`() {
        assertNull(widgetNextRefreshAt(null, suite(), emptySet(), now))
    }
    @Test fun `static roster and year wait for civil midnight rather than polling each minute`() {
        val midnight = Instant.parse("2026-10-29T00:00:00Z").toEpochMilli()
        assertEquals(midnight, widgetNextRefreshAt(null, suite(), setOf(DoneAtWidgetKind.YEAR, DoneAtWidgetKind.ROSTER), now))
    }
    @Test fun `civil refresh respects daylight saving rather than adding twenty four hours`() {
        val date = Instant.parse("2026-03-08T06:30:00Z").toEpochMilli()
        assertEquals(Instant.parse("2026-03-09T04:00:00Z").toEpochMilli(),
            widgetNextRefreshAt(null, suite("America/New_York"), setOf(DoneAtWidgetKind.YEAR), date))
    }
    @Test fun `only installed active focus gets minute cadence`() {
        val focus = WidgetFocusPayload(WidgetAccess(true), listOf(WidgetFocusBlock("Task", startMs = now - 60_000, endMs = now + 600_000, isRunning = true)))
        val snapshot = suite(focus = focus)
        assertEquals((now / 60_000 + 1) * 60_000, widgetNextRefreshAt(null, snapshot, setOf(DoneAtWidgetKind.FOCUS), now))
        assertEquals(Instant.parse("2026-10-29T00:00:00Z").toEpochMilli(), widgetNextRefreshAt(null, snapshot, setOf(DoneAtWidgetKind.YEAR), now))
    }
    @Test fun `idle planned focus waits for its actual boundary`() {
        val start = now + 10 * 60_000
        val focus = WidgetFocusPayload(WidgetAccess(true), listOf(WidgetFocusBlock("Task", startMs = start, endMs = start + 600_000)))
        assertEquals(start, widgetNextRefreshAt(null, suite(focus = focus), setOf(DoneAtWidgetKind.FOCUS), now))
    }
}
