package com.rainif.doneat.core.domain.widget

import com.rainif.doneat.core.domain.records.*
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.session.SessionEnvironment
import com.rainif.doneat.core.domain.session.SessionState
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.core.domain.settings.PreferencesRules
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

/** Regression for a real first-run default schedule before any Records period has been saved. */
class WidgetSuiteFreshScheduleTest {
    private val zone = ZoneId.of("Asia/Taipei")
    private fun at(day: String, hour: Int = 0) = LocalDate.parse(day).atTime(hour, 0).atZone(zone).toInstant().toEpochMilli()
    private val now = at("2026-10-29", 10)
    private val prefs = PreferencesRules.defaults(zone.id, now.toDouble())

    private fun compose(state: RecordState): WidgetSuiteSnapshot {
        val env = SessionEnvironment(prefs, true, null, emptyList(), HolidayCalendar.EMPTY, zone.id).with(state)
        val session = ShiftSession(SessionState(), env)
        val queries = RecordsQueries(state, env.holidays, zone, true, currentHours = session.hoursConfiguration(now.toDouble()), firstDayOfWeek = DayOfWeek.SUNDAY)
        return WidgetSuiteComposer.compose(session, queries, now, "en", WidgetAccess(true))
    }

    @Test fun committedDefaultPreferencesProjectMonToFriWithoutInventingRecordHistory() {
        val state = RecordState(syncedPreferences = prefs)
        val suite = compose(state)
        val week = suite.calendar.week(now)
        assertEquals(listOf("2026-10-25", "2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31"), week.map { it.dayKey })
        assertEquals(listOf(false, true, true, true, true, true, false), week.map { it.isWork })
        assertEquals(listOf(0L, 8L, 8L, 8L, 8L, 8L, 0L), week.map { it.workMs / 3_600_000 })
        assertEquals(at("2026-10-29", 9), week[4].startAtMs)
        assertEquals(at("2026-10-29", 17), week[4].endAtMs)
        assertEquals(40 * 3_600_000L, WidgetWeekProgress.from(suite.calendar, now).totalMs)
        assertEquals(0.625, suite.calendar.weekProgress(now), 0.0000001)
        assertTrue(suite.summary.periods.all { it.workedMs == 0L })
        assertTrue(state.periods.isEmpty())
        assertTrue(state.snapshots.isEmpty())
        assertTrue(state.observations.isEmpty())
    }

    @Test fun freshScheduleFallbackStillUsesTheRealOverrideAndLeaveLayersExactlyOnce() {
        val state = RecordState(syncedPreferences = prefs,
            overrides = listOf(DayOverride("2026-10-28", DayOverrideKind.NOT_WORKING, emptyList(), null, now.toDouble(), 1, "override", zone.id)),
            leaveDays = listOf(
                LeaveDay("2026-10-29", "firstHalf", emptyList(), null, zone.id, now.toDouble(), 1, "half"),
                LeaveDay("2026-10-30", "whole", emptyList(), null, zone.id, now.toDouble(), 1, "whole"),
            ))
        val days = compose(state).calendar.days.associateBy { it.dayKey }
        assertEquals(WidgetCalendarDayKind.REST, days.getValue("2026-10-28").kind)
        assertEquals(0L, days.getValue("2026-10-28").workMs)
        val half = days.getValue("2026-10-29")
        assertEquals(4 * 3_600_000L, half.workMs)
        assertEquals(at("2026-10-29", 13), half.startAtMs)
        assertEquals(at("2026-10-29", 17), half.endAtMs)
        assertEquals(WidgetCalendarDayKind.LEAVE, days.getValue("2026-10-30").kind)
        assertEquals(0L, days.getValue("2026-10-30").workMs)
    }

    @Test fun existingArchivedHoursRemainAuthoritativeOverDifferentLivePreferences() {
        val old = SnapshotHours("08:00", "12:00", listOf(1, 2, 3, 4, 5), "classic", breakStartTime = null, breakDurationMinutes = 0)
        var id = 0
        val context = RecordEditContext(at("2026-10-01").toDouble(), zone.id, true, HolidayCalendar.EMPTY,
            currentHours = { old }, newId = { "old-${++id}" })
        val state = RecordEdits.ensureSeeded(RecordState(syncedPreferences = prefs), old, context)
        val day = compose(state).calendar.days.first { it.dayKey == "2026-10-29" }
        assertEquals(at("2026-10-29", 8), day.startAtMs)
        assertEquals(at("2026-10-29", 12), day.endAtMs)
        assertEquals(4 * 3_600_000L, day.workMs)
        assertEquals(1, state.periods.size)
        assertEquals(1, state.snapshots.size)
    }
}
