package com.rainif.doneat.core.domain.widget

import com.rainif.doneat.core.domain.records.SyncedPreferences
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.session.SessionCommands
import com.rainif.doneat.core.domain.session.SessionEnvironment
import com.rainif.doneat.core.domain.session.SessionState
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.core.domain.session.TimelineEvent
import com.rainif.doneat.core.domain.session.UpcomingTimeline
import com.rainif.doneat.core.domain.settings.PreferencesRules
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * iOS `OffWorkStoreTests` widget cases on the Kotlin composer. Device and
 * records zones are both UTC, so calendar days are plain dates.
 */
class WidgetSnapshotTest {
    private class Harness(scheduleMode: String, start: Int = 9 * 60, end: Int = 17 * 60, lunch: Pair<Int, Int>? = null) {
        val prefs: SyncedPreferences = PreferencesRules.defaults(ZONE, 0.0).copy(
            scheduleMode = scheduleMode, workdays = listOf(1, 2, 3, 4, 5), startMinutes = start, endMinutes = end,
            lunchEnabled = lunch != null, lunchStartMinutes = lunch?.first ?: 12 * 60, lunchDurationMinutes = lunch?.second ?: 60,
        )
        var state = SessionState()
        private var ids = 0
        val env get() = SessionEnvironment(prefs, onboardingComplete = true, extendedSchedule = null, rosterDays = emptyList(), holidays = HolidayCalendar.EMPTY, deviceZone = ZONE)
        val session get() = ShiftSession(state, env)
        fun run(command: SessionCommands.() -> com.rainif.doneat.core.domain.session.SessionResult) {
            val result = SessionCommands(env) { "id-${++ids}" }.command()
            assertTrue(result.accepted)
            state = result.state
        }

        fun snapshot(nowMs: Long): WidgetSnapshot {
            val words: (TimelineEvent) -> Pair<String, String> = { it.kind.name to "" }
            val upcoming = WidgetUpcoming(session, { shift, at -> UpcomingTimeline.events(shift, at, emptyList(), false, false) }, words)
            return WidgetSnapshotComposer.compose(session, nowMs, "en", WidgetSnapshotComposer.futureShifts(session, nowMs), upcoming)
        }
    }

    private fun at(day: Int, hour: Int, minute: Int = 0) =
        LocalDateTime.of(2026, 8, day, hour, minute).atZone(ZoneId.of(ZONE)).toInstant().toEpochMilli()

    @Test fun `the timeline has an entry covering the lunch break`() {
        val h = Harness("off", end = 18 * 60, lunch = 12 * 60 + 30 to 60)
        h.run { start(h.state, at(24, 9).toDouble()) }
        val now = at(24, 12, 45)
        val current = h.snapshot(now).entry(now)!!
        assertEquals(WidgetPhase.BREAK, current.phase)
        assertEquals("lunchInProgress", current.labelKey)
        assertEquals(at(24, 13, 30), current.timerEndAtMs)
    }

    @Test fun `overtime is its own label but the same working countdown`() {
        val h = Harness("classic")
        h.run { start(h.state, at(24, 16).toDouble()) }
        h.run { applyOvertime(h.state, at(24, 20).toDouble(), at(24, 16).toDouble()) }
        val widget = h.snapshot(at(24, 16))
        assertEquals("widgetWorking", widget.entry(at(24, 16, 30))!!.labelKey)
        val overtime = widget.entry(at(24, 18))!!
        assertEquals(WidgetPhase.WORKING, overtime.phase)
        assertEquals("overtime", overtime.labelKey)
        assertEquals(WidgetCountdownKind.WORK_REMAINING, overtime.countdownKind)
        assertTrue(abs(overtime.countdownTargetAtMs!! - at(24, 20)) < 1_000)
    }

    @Test fun `a rest day keeps its own label even though it counts down`() {
        val h = Harness("classic")
        val saturday = at(29, 10)
        val current = h.snapshot(saturday).entry(saturday)!!
        assertEquals("widgetRestDay", current.labelKey)
        assertNotNull(current.countdownTargetAtMs)
        // From the workday's midnight the copy becomes the ordinary pre-work countdown.
        assertEquals("nextShiftLabelShort", h.snapshot(saturday).entry(at(31, 8))!!.labelKey)
    }

    @Test fun `coming up carries the timer's rows and nothing already past`() {
        val h = Harness("off", end = 18 * 60, lunch = 12 * 60 + 30 to 60)
        h.run { start(h.state, at(24, 9).toDouble()) }
        val now = at(24, 10)
        val upcoming = h.snapshot(now).upcoming
        assertTrue(upcoming.any { it.kind == "lunchStart" })
        assertTrue(upcoming.any { it.kind == "lunchEnd" })
        assertTrue(upcoming.any { it.kind == "shiftEnd" })
        assertTrue(upcoming.all { it.dateMs > now && it.title.isNotEmpty() })
    }

    @Test fun `a recurring snapshot keeps coming-up rows far ahead`() {
        val h = Harness("classic", lunch = 12 * 60 to 60)
        val now = at(24, 10)
        val upcoming = h.snapshot(now).upcoming
        assertTrue(upcoming.any { it.kind == "shiftStart" && it.dateMs == at(26, 9) })
        assertTrue(upcoming.any { it.dateMs > now + 36 * 3_600_000 })
    }

    @Test fun `a rest day projects no phantom shift`() {
        val h = Harness("classic", lunch = 12 * 60 to 60)
        val saturday = at(22, 10)
        assertFalse(h.session.snapshot(saturday.toDouble())!!.isWorkday)
        val upcoming = h.snapshot(saturday).upcoming
        assertTrue(upcoming.none { Instant.ofEpochMilli(it.dateMs).atZone(ZoneId.of(ZONE)).dayOfWeek == DayOfWeek.SATURDAY })
        assertTrue(upcoming.any { it.kind == "shiftStart" && it.dateMs == at(24, 9) })
    }

    @Test fun `while working the target is the planned clock-off, not remaining work on the clock`() {
        val h = Harness("off", end = 19 * 60, lunch = 12 * 60 + 30 to 90)
        h.run { start(h.state, at(24, 9).toDouble()) }
        val now = at(24, 10)
        val current = h.snapshot(now).entry(now)!!
        assertEquals(WidgetPhase.WORKING, current.phase)
        assertTrue(abs(current.countdownTargetAtMs!! - at(24, 19)) < 1_000)
        // The ticking countdown is effective work: it skips lunch, so it ends well before 19:00.
        assertTrue(abs(current.countdownTargetAtMs!! - current.timerEndAtMs!!) > 30 * 60_000)
    }

    @Test fun `later shifts start on their own without reopening the app`() {
        val h = Harness("classic")
        val widget = h.snapshot(at(24, 8))
        val tuesday = widget.entry(at(25, 10))!!
        assertEquals(WidgetPhase.WORKING, tuesday.phase)
        assertEquals("widgetWorking", tuesday.labelKey)
        // Done for today until midnight, then the next morning's countdown.
        assertEquals("offWorkToday", widget.entry(at(24, 20))!!.labelKey)
        assertEquals("nextShiftLabelShort", widget.entry(at(25, 7))!!.labelKey)
    }

    @Test fun `consecutive overnight shifts do not keep the previous done state`() {
        val h = Harness("classic", start = 23 * 60, end = 7 * 60)
        val widget = h.snapshot(at(24, 8))
        assertEquals(WidgetPhase.WORKING, widget.entry(at(25, 23, 30))!!.phase)
    }

    @Test fun `an early clock-off is done for the rest of that day`() {
        val h = Harness("classic")
        h.run { start(h.state, at(24, 9).toDouble()) }
        h.run { clockOffEarly(h.state, at(24, 12).toDouble()) }
        val widget = h.snapshot(at(24, 12))
        assertEquals(WidgetPhase.DONE, widget.entry(at(24, 12, 5))!!.phase)
        assertEquals(WidgetPhase.DONE, widget.entry(at(24, 16))!!.phase)
    }

    @Test fun `working progress advances inside an interval`() {
        val h = Harness("off")
        h.run { start(h.state, at(24, 9).toDouble()) }
        val widget = h.snapshot(at(24, 9))
        assertEquals(50.0, widget.entry(at(24, 13))!!.progressAtDate, 0.01)
    }

    @Test fun `a stale or unreadable snapshot has no entry, and the codec round-trips`() {
        val h = Harness("classic")
        val widget = h.snapshot(at(24, 10))
        assertNull(widget.entry(widget.expiresAtMs))
        assertNull(widget.entry(widget.generatedAtMs - 1))
        assertNull(WidgetSnapshot.decode("{"))
        assertEquals(widget, WidgetSnapshot.decode(widget.encode()))
    }

    @Test fun `nothing in the snapshot mentions money`() {
        val h = Harness("classic", lunch = 12 * 60 to 60)
        val text = h.snapshot(at(24, 10)).encode()
        listOf("salary", "earn", "income", "money", "wage").forEach { assertFalse(it, text.contains(it, ignoreCase = true)) }
    }

    private companion object {
        const val ZONE = "UTC"
    }
}
