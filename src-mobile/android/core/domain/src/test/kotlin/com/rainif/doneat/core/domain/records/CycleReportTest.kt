package com.rainif.doneat.core.domain.records

import org.junit.Assert.*
import org.junit.Test
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import com.rainif.doneat.core.domain.schedule.HolidayCalendar

class CycleReportTest {
    private val zone = ZoneId.of("America/New_York")
    private fun now(date: String) = java.time.ZonedDateTime.parse(date).toInstant().toEpochMilli().toDouble()

    @Test fun periodsRespectWeekStartAndLeapYear() {
        val sunday = CycleReportPeriod.containing(LocalDate.parse("2024-02-29"), CycleReportKind.WEEK, zone, DayOfWeek.SUNDAY)
        assertEquals("2024-02-25", sunday.startDayKey)
        assertEquals("2024-02-18", sunday.neighbour(-1, DayOfWeek.MONDAY).startDayKey)
        val year = CycleReportPeriod.containing(LocalDate.parse("2024-02-29"), CycleReportKind.YEAR, zone)
        assertEquals(366, year.dayKeys.size)
        assertEquals(year, CycleReportPeriod.fromUrl(year.url))
        assertNull(CycleReportPeriod.fromUrl(year.url.replace("2024-01-01", "2024-01-02")))
        assertNull(CycleReportPeriod.fromUrl(year.url.replace("America%2FNew_York", "Invalid")))
    }

    @Test fun firstMorningSchedulesJustCompletedPeriodsIndependently() {
        val instant = now("2026-01-01T08:59:00-05:00[America/New_York]")
        val all = CycleReportNotificationPlan.items(true, true, true, instant, zone, DayOfWeek.MONDAY)
        assertEquals(3, all.size)
        assertEquals("2025-01-01", all.first { it.kind == CycleReportKind.YEAR }.startDayKey)
        assertEquals("2025-12-01", all.first { it.kind == CycleReportKind.MONTH }.startDayKey)
        val after = CycleReportNotificationPlan.items(false, false, true, instant + 60_000, zone, DayOfWeek.MONDAY)
        assertEquals("2026-01-01", after.single().startDayKey)
    }

    @Test fun historicalReferenceAndFrozenPayloadDoNotFollowToday() {
        val period = CycleReportPeriod.containing(LocalDate.parse("2024-02-10"), CycleReportKind.MONTH, zone)
        assertEquals(LocalDate.parse("2024-02-29"), period.referenceDate(now("2026-10-03T12:00:00-04:00[America/New_York]")))
        assertEquals(period, CycleReportPeriod.fromUrl(period.url))
        assertFalse(period.url.contains("salary"))
        assertFalse(period.url.contains("income"))
    }

    @Test fun incomeRemovalIncludesEveryMonth() {
        val period = CycleReportPeriod.containing(LocalDate.parse("2024-02-10"), CycleReportKind.YEAR, zone)
        val figures = CycleReportFigures(2, 3_600_000, 300_000, 50.0)
        val snapshot = CycleReportSnapshot(period, emptyList(), figures, 0, 0, null, false,
            pay = CycleReportPay(50.0, 50.0, 5.0), months = listOf(CycleReportMonth(period, figures, 0, 1)))
        val hidden = snapshot.withoutIncome()
        assertNull(hidden.income)
        assertNull(hidden.pay)
        assertNull(hidden.months.single().figures.income)
    }

    @Test fun unauthorizedQueriesNeverBuildReport() {
        val period = CycleReportPeriod.containing(LocalDate.parse("2026-10-03"), CycleReportKind.YEAR, zone)
        assertNull(RecordsQueries(RecordState(), HolidayCalendar.EMPTY, zone, false).cycleReportSnapshot(period, 0.0))
    }

    @Test fun uncoveredFutureDatesDoNotInventLongBreaks() {
        val period = CycleReportPeriod.containing(LocalDate.parse("2026-10-03"), CycleReportKind.MONTH, zone)
        val snapshot = RecordsQueries(RecordState(), HolidayCalendar.EMPTY, zone, true).cycleReportSnapshot(period,
            now("2026-10-03T12:00:00-04:00[America/New_York]"))!!
        assertNull(snapshot.ahead)
    }

    @Test fun futureYearDaysNeverCountAsRestOrWork() {
        val period = CycleReportPeriod.containing(LocalDate.parse("2026-10-03"), CycleReportKind.YEAR, zone)
        val snapshot = RecordsQueries(RecordState(), HolidayCalendar.EMPTY, zone, true).cycleReportSnapshot(period,
            now("2026-10-03T12:00:00-04:00[America/New_York]"))!!
        assertEquals(12, snapshot.months.size)
        assertTrue(snapshot.isInProgress)
        assertEquals(0, snapshot.restDayCount)
        assertEquals(0, snapshot.months.last().restDayCount)
        assertNull(snapshot.ahead)
        assertNull(snapshot.baseline)
    }
}
