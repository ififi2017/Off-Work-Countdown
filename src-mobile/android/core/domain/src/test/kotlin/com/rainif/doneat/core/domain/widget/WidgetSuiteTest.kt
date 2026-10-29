package com.rainif.doneat.core.domain.widget

import com.rainif.doneat.core.domain.records.*
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.session.*
import com.rainif.doneat.core.domain.settings.PreferencesRules
import java.io.File
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class WidgetSuiteTest {
    private val utc = ZoneId.of("UTC")
    private val now = Instant.parse("2026-10-28T10:00:00Z").toEpochMilli()
    private fun at(day: String, hour: Int = 0, zone: ZoneId = utc) = LocalDate.parse(day).atTime(hour, 0).atZone(zone).toInstant().toEpochMilli()

    private fun compose(
        access: WidgetAccess = WidgetAccess(true), zone: ZoneId = utc, first: DayOfWeek = DayOfWeek.MONDAY,
        mode: String = "classic", start: Int = 540, end: Int = 1_020, atMs: Long = now,
        focus: List<WidgetFocusBlock> = emptyList(),
    ): Pair<WidgetSuiteSnapshot, RecordsQueries> {
        val prefs = PreferencesRules.defaults(zone.id, atMs.toDouble()).copy(scheduleMode = mode, startMinutes = start, endMinutes = end,
            salaryEnabled = true, salaryAmount = "987654.32", lunchEnabled = true, lunchStartMinutes = 720, lunchDurationMinutes = 60)
        val hours = SnapshotHours("%02d:%02d".format(start / 60, start % 60), "%02d:%02d".format(end / 60, end % 60),
            listOf(1, 2, 3, 4, 5), mode, breakStartTime = "12:00", breakDurationMinutes = 60)
        var id = 0
        val context = RecordEditContext(atMs.toDouble(), zone.id, true, HolidayCalendar.EMPTY, currentHours = { hours }, newId = { "fixture-${++id}" })
        val archive = RecordEdits.ensureSeeded(RecordState(), hours, context)
        val session = ShiftSession(SessionState(), SessionEnvironment(prefs, true, null, emptyList(), HolidayCalendar.EMPTY, zone.id))
        val queries = RecordsQueries(archive, HolidayCalendar.EMPTY, zone, authorized = access.isUnlocked(atMs), currentHours = hours, firstDayOfWeek = first)
        return WidgetSuiteComposer.compose(session, queries, atMs, "en", access, focus) to queries
    }

    @Test fun suiteRoundTripsWithoutMoneyOrSourceArchiveFields() {
        val suite = compose(focus = listOf(WidgetFocusBlock("Write", "writing", now, now + 1_000))).first
        val json = suite.encode()
        assertEquals(suite, WidgetSuiteSnapshot.decode(json))
        for (forbidden in listOf("salary", "income", "earnings", "purchaseToken", "987654.32", "observations", "syncedPreferences")) {
            assertFalse(forbidden, json.contains(forbidden, ignoreCase = true))
        }
        assertNull(WidgetSuiteSnapshot.decode(json.replace("\"schemaVersion\":1", "\"schemaVersion\":9")))
        assertNull(WidgetSuiteSnapshot.decode("{}"))
        val subscribed = compose(access = WidgetAccess(true, now + 100)).first.encode()
        assertNull(WidgetSuiteSnapshot.decode(subscribed.replace("\"validUntilMs\":${now + 100}", "\"validUntilMs\":\"invalid\"")))
        assertNull(WidgetSuiteSnapshot.decode(subscribed.replace("\"validUntilMs\":${now + 100}", "\"validUntilMs\":9223372036854775808")))
    }

    @Test fun expiredOrUnavailableAccessContainsNoPaidDataButKeepsFreeCalendarAndHoliday() {
        val suite = compose(access = WidgetAccess(true, now + 1), focus = listOf(WidgetFocusBlock("Private task", startMs = now, endMs = now + 9_000))).first
        val withPrivate = suite.copy(life = WidgetLifePayload(suite.summary.access, bornDay = 7_000),
            holiday = WidgetHolidayPayload(suite.summary.access, weekendStartMs = now + 100,
                nextHoliday = WidgetHoliday("Holiday", "2026-12-25", now + 100, "2026-12-25", 1, false),
                nextLeave = WidgetLeave("2026-12-01", now + 20, 2.0, 4, emptyList()), leaveRemainingDays = 10.0,
                labels = mapOf("remaining" to "10", "requested" to "2", "untilRest" to "Weekend")))
        val expired = WidgetSuiteSnapshot.decode(withPrivate.encode())!!.redacted(now + 1)
        assertTrue(expired.summary.periods.isEmpty())
        assertTrue(expired.summary.liveSegments.isEmpty())
        assertNull(expired.life.bornDay)
        assertTrue(expired.focus.blocks.isEmpty())
        assertNull(expired.holiday.nextLeave)
        assertNull(expired.holiday.leaveRemainingDays)
        assertFalse(expired.holiday.labels.containsKey("remaining"))
        assertEquals("Holiday", expired.holiday.nextHoliday?.name)
        assertEquals(withPrivate.calendar, expired.calendar)
        assertEquals(expired, expired.redacted(now + 2))
        val free = compose(access = WidgetAccess.LOCKED, focus = listOf(WidgetFocusBlock("Must not leak", startMs = now, endMs = now + 9_000))).first
        assertTrue(free.focus.blocks.isEmpty())
        assertTrue(free.summary.periods.isEmpty())
        assertFalse(free.encode().contains("Must not leak"))
    }

    @Test fun calendarAndSummaryUseTheSameChosenFirstWeekdayAndExistingReports() {
        for (first in listOf(DayOfWeek.MONDAY, DayOfWeek.SUNDAY)) {
            val (suite, queries) = compose(first = first)
            assertEquals(first.value, suite.calendar.firstDayOfWeek)
            assertEquals(first, LocalDate.parse(suite.calendar.week(now).first().dayKey).dayOfWeek)
            val period = suite.summary.period(WidgetSummaryPeriodKind.WEEK)!!
            val source = queries.cycleReportSnapshot(queries.reportPeriod(CycleReportKind.WEEK, queries.today(now.toDouble())), now.toDouble())!!
            assertEquals(source.figures.workedMs, period.workedMs)
            assertEquals(source.figures.overtimeMs, period.overtimeMs)
            assertEquals(source.figures.workdays, period.workdays)
            assertEquals(source.period.startDayKey, period.startDayKey)
            assertEquals(source.days.map { it.workMs }, period.bars.map { it.valueMs })
            assertEquals(12, suite.summary.period(WidgetSummaryPeriodKind.YEAR)!!.bars.size)
        }
    }

    @Test fun countdownGeometryKeepsLunchGapsAndOvernightShiftDates() {
        val lunch = compose().first.countdownSegments
        assertEquals(2, lunch.size)
        assertEquals(at("2026-10-28", 12), lunch.first().endMs)
        assertEquals(at("2026-10-28", 13), lunch.last().startMs)
        val nightAt = at("2026-10-29", 2)
        val night = compose(start = 22 * 60, end = 6 * 60, atMs = nightAt).first.countdownSegments
        assertEquals(at("2026-10-28", 22), night.first().startMs)
        assertEquals(at("2026-10-29", 6), night.last().endMs)
        assertEquals(8 * 3_600_000L, night.sumOf { it.durationMs })
        assertTrue(compose(mode = "off").first.calendar.days.isEmpty())
    }

    @Test fun weekdayProgressUsesEffectiveSegmentsRatherThanWallTimeAcrossLunchAndOvernight() {
        val monday = WidgetCalendarDay("2026-10-26", at("2026-10-26"), WidgetCalendarDayKind.WORK,
            segments = listOf(WidgetTimeSegment(at("2026-10-26", 9), at("2026-10-26", 12)), WidgetTimeSegment(at("2026-10-26", 13), at("2026-10-26", 17))))
        val tuesday = WidgetCalendarDay("2026-10-27", at("2026-10-27"), WidgetCalendarDayKind.WORK,
            segments = listOf(WidgetTimeSegment(at("2026-10-27", 22), at("2026-10-28", 6))))
        val wednesday = WidgetCalendarDay("2026-10-28", at("2026-10-28"), WidgetCalendarDayKind.REST)
        val payload = WidgetCalendarPayload("UTC", 1, WidgetCalendarScheduleKind.WEEKLY, listOf(monday, tuesday, wednesday))
        assertEquals(15 * 3_600_000L, WidgetWeekProgress.from(payload, at("2026-10-26", 12)).totalMs)
        assertEquals(12 * 3_600_000L, WidgetWeekProgress.from(payload, at("2026-10-26", 12)).remainingMs)
        assertEquals(payload.weekProgress(at("2026-10-26", 12)), payload.weekProgress(at("2026-10-26", 13)), 0.0)
        assertEquals(4 * 3_600_000L, WidgetWeekProgress.from(payload, at("2026-10-28", 2)).remainingMs)
        assertEquals(0.5, WidgetWeekProgress.from(payload, at("2026-10-28", 2)).remainingDays, 0.0)
    }

    @Test fun localCalendarDayAndProgressRespectDstAndLeapYears() {
        val zone = ZoneId.of("America/Los_Angeles")
        val springNoon = LocalDate.parse("2026-03-08").atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
        val spring = WidgetCalendarProgress.at(springNoon, zone, DayOfWeek.SUNDAY)
        assertEquals(11.0 / 23.0, spring.today, 0.000001)
        val autumnNoon = LocalDate.parse("2026-11-01").atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
        assertEquals(13.0 / 25.0, WidgetCalendarProgress.at(autumnNoon, zone, DayOfWeek.SUNDAY).today, 0.000001)
        val leap = WidgetCalendarProgress.at(at("2028-01-01"), utc, DayOfWeek.MONDAY)
        assertEquals(366, leap.daysLeftInYear)
        val payload = WidgetCalendarPayload(zone.id, 1, WidgetCalendarScheduleKind.WEEKLY,
            listOf(WidgetCalendarDay("2026-03-08", at("2026-03-08", zone = zone), WidgetCalendarDayKind.REST)))
        assertNotNull(payload.day(at("2026-03-09", zone = zone) - 1))
        assertNull(payload.day(at("2026-03-09", zone = zone)))
    }

    @Test fun summaryLiveHoursSkipBreaksAndFocusSelectsHalfOpenIntervals() {
        val period = WidgetSummaryPeriod(WidgetSummaryPeriodKind.WEEK, "", null, "2026-10-26", "2026-11-01", 2 * 3_600_000L, 0, 1, 5, 4, 0.2)
        val live = listOf(WidgetTimeSegment(at("2026-10-28", 9), at("2026-10-28", 12)), WidgetTimeSegment(at("2026-10-28", 13), at("2026-10-28", 17)))
        assertEquals(4 * 3_600_000L, period.workedMs(live, at("2026-10-28", 10), at("2026-10-28", 13)))
        val work = WidgetFocusBlock("Work", startMs = now, endMs = now + 1_000, isRunning = true)
        val rest = WidgetFocusBlock("Rest", startMs = now + 1_000, endMs = now + 2_000, isBreak = true, isRunning = true)
        val next = WidgetFocusBlock("Next", startMs = now + 2_000, endMs = now + 3_000)
        val focus = WidgetFocusPayload(WidgetAccess(true), listOf(work, rest, next))
        assertEquals(rest, focus.current(now + 1_000))
        assertEquals(next, focus.next(now))
        assertNull(focus.current(now + 3_000))
        assertNull(focus.current(now + 2_500))
        val legacy = compose(focus = listOf(next)).first.encode().replace(",\"isRunning\":false", "")
        assertFalse(WidgetSuiteSnapshot.decode(legacy)!!.focus.blocks.single().isRunning)
    }

    @Test fun lifeFiguresUseTheSameIosYearAndMonthConstantsAndRespectExpiry() {
        val today = LocalDate.parse("2026-10-28").toEpochDay()
        val life = WidgetLifePayload(WidgetAccess(true, now + 1), bornDay = today - 10_000, careerStartDay = today - 1_000, retirementDay = today + 2_000)
        val figures = WidgetLifeFigures.from(life, now, utc)!!
        assertEquals(10_000, figures.daysLived)
        assertEquals(10_000 / (80 * 365.2425), figures.lifeShare, 0.0000001)
        assertEquals(1.0 / 3.0, figures.careerShare!!, 0.0000001)
        assertEquals((1_000 / 30.436875).toInt(), figures.monthsWorked)
        assertEquals((2_000 / 30.436875).toInt(), figures.monthsToRetirement)
        assertNull(WidgetLifeFigures.from(life, now + 1, utc))
        for (zone in listOf(ZoneId.of("Pacific/Kiritimati"), ZoneId.of("Pacific/Auckland"))) {
            val localNow = at("2026-10-29", 1, zone)
            val localMidnight = at("2026-10-29", zone = zone)
            val ordinal = kotlin.math.floor(localMidnight / 86_400_000.0 + 0.5).toLong()
            val localLife = WidgetLifePayload(WidgetAccess(true), bornDay = ordinal - 10)
            assertEquals(10L, WidgetLifeFigures.from(localLife, localNow, zone)!!.daysLived)
            val suite = compose(zone = zone, atMs = localNow).first
            assertEquals(zone.id, suite.lifeTimeZoneIdentifier)
            assertEquals(zone.id, WidgetSuiteSnapshot.decode(suite.encode())!!.lifeTimeZoneIdentifier)
        }
    }

    @Test fun regionalHolidaysUseBundledCoverageAndNeverMakeUpUnknownYears() {
        val holidays = HolidayCalendar.parse(File(System.getProperty("owc.holidayTemplates")).readText())
        val holiday = WidgetSuiteComposer.nextHoliday(holidays, "CN", LocalDate.parse("2026-09-28"), utc, "zh-CN")!!
        assertEquals("2026-10-01", holiday.startDayKey)
        assertTrue(holiday.days >= 1)
        assertTrue(holiday.name.isNotBlank())
        val lastYear = holidays.coveredThroughYear("CN")!!
        assertNull(WidgetSuiteComposer.nextHoliday(holidays, "CN", LocalDate.of(lastYear + 1, 1, 1), utc, "en"))
        assertNull(WidgetSuiteComposer.nextHoliday(holidays, null, LocalDate.parse("2026-10-01"), utc, "en"))
    }

    @Test fun holidayRunUsesTheCallersRegionalWeekendAndDoesNotAttachSunday() {
        val holidays = HolidayCalendar.parse(File(System.getProperty("owc.holidayTemplates")).readText())
        // Egypt's named Thursday holiday joins its Friday/Saturday weekend.
        val holiday = WidgetSuiteComposer.nextHoliday(holidays, "EG", LocalDate.parse("2026-07-23"), utc, "en",
            weekendDays = setOf(DayOfWeek.FRIDAY, DayOfWeek.SATURDAY))!!
        assertEquals("2026-07-23", holiday.startDayKey)
        assertEquals("2026-07-25", holiday.endDayKey)
        assertEquals(3, holiday.days)
        // A caller whose weekend is Saturday/Sunday must not attach Friday.
        val ordinary = WidgetSuiteComposer.nextHoliday(holidays, "EG", LocalDate.parse("2026-07-23"), utc, "en")!!
        assertEquals("2026-07-23", ordinary.endDayKey)
        assertEquals(1, ordinary.days)
    }
}
