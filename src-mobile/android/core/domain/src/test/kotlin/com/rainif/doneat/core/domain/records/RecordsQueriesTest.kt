package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.records.RecordTestFixtures.ms
import com.rainif.doneat.core.domain.records.RecordTestFixtures.segment
import com.rainif.doneat.core.domain.salary.SalarySettings
import com.rainif.doneat.core.domain.salary.SalaryType
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.ScheduleRuleInput
import com.rainif.doneat.core.domain.schedule.ScheduleRules
import com.rainif.doneat.core.domain.session.SessionCommands
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId

/**
 * The Records read side over a real archive: what each cell says, what it
 * counts, what a locked view is allowed to carry, and that estimates never
 * become rows.
 */
class RecordsQueriesTest {
    private val weekdays = SnapshotHours("09:00", "18:00", listOf(1, 2, 3, 4, 5), "classic", breakStartTime = "12:00", breakDurationMinutes = 60)
    private val nights = SnapshotHours("22:00", "06:00", listOf(1, 2, 3, 4, 5), "classic", breakStartTime = null, breakDurationMinutes = 0)
    private var ids = 0
    private val zone = ZoneId.of(RecordTestFixtures.ZONE)

    /** Records began Monday 2026-09-07; "now" is Wednesday 2026-09-16 at 10:00. */
    private val now = ms("2026-09-16", 10)

    private fun seeded(hours: SnapshotHours = weekdays, from: String = "2026-09-07"): RecordState = RecordEdits.ensureSeeded(
        RecordState(), hours,
        RecordEditContext(
            nowMs = ms(from, 10), recordsTimeZone = RecordTestFixtures.ZONE, canEdit = true, holidays = HolidayCalendar.EMPTY,
            currentHours = { hours }, newId = { "00000000-0000-4000-8000-%012d".format(++ids) },
        ),
    )

    private fun queries(state: RecordState, authorized: Boolean = true, salary: SalarySettings? = null, currentHours: SnapshotHours? = null) =
        RecordsQueries(state, HolidayCalendar.EMPTY, zone, authorized, salary = salary, dailySalary = salary?.let { 500.0 }, currentHours = currentHours)

    private fun observation(day: String, kind: WorkObservationKind, hour: Int, valueData: String? = null) = WorkObservation(
        "00000000-0000-4000-9000-%012d".format(++ids), day, ms(day, hour), kind, valueData, "", 2, RecordTestFixtures.ZONE, ms(day, hour), 1,
        "00000000-0000-4000-9000-%012d".format(ids),
    )

    private fun week(q: RecordsQueries, anchor: String): List<RecordsDayCell> {
        val (first, last) = q.window(RecordsScale.WEEK, LocalDate.parse(anchor))
        return q.cells(q.displayDays(first.minusDays(1), last, now), first, now)
    }

    @Test fun windowsFollowTheLanguagesFirstWeekday() {
        val monday = RecordsQueries(RecordState(), HolidayCalendar.EMPTY, zone, true)
        val sunday = RecordsQueries(RecordState(), HolidayCalendar.EMPTY, zone, true, firstDayOfWeek = DayOfWeek.SUNDAY)
        val wednesday = LocalDate.parse("2026-09-16")
        assertEquals(LocalDate.parse("2026-09-14") to LocalDate.parse("2026-09-20"), monday.window(RecordsScale.WEEK, wednesday))
        assertEquals(LocalDate.parse("2026-09-13") to LocalDate.parse("2026-09-19"), sunday.window(RecordsScale.WEEK, wednesday))
        assertEquals(LocalDate.parse("2026-09-01") to LocalDate.parse("2026-09-30"), monday.window(RecordsScale.MONTH, wednesday))
        assertEquals(LocalDate.parse("2026-01-01") to LocalDate.parse("2026-12-31"), monday.window(RecordsScale.YEAR, wednesday))
        assertEquals(1, monday.gridLeadingBlanks(LocalDate.parse("2026-09-01")))
        assertEquals(2, sunday.gridLeadingBlanks(LocalDate.parse("2026-09-01")))
    }

    @Test fun anElapsedSavedScheduleCountsAsWorkWithoutAnyAppVisit() {
        val cells = week(queries(seeded()), "2026-09-14")
        val byDay = cells.associateBy { it.dayKey }
        val monday = byDay.getValue("2026-09-14")
        assertEquals(RecordsDayAppearance.RECORDED, monday.appearance)
        assertTrue(monday.isFromSavedSchedule)
        assertEquals(8 * 3_600_000L, monday.workMs)
        assertEquals(3_600_000L, monday.breakMs)
        // Today is counted up to now and planned after it; tomorrow is only planned.
        assertTrue(byDay.getValue("2026-09-16").isToday)
        assertEquals(RecordsDayAppearance.PLANNED, byDay.getValue("2026-09-17").appearance)
        assertEquals(RecordsDayAppearance.REST, byDay.getValue("2026-09-19").appearance)
        assertEquals(0L, byDay.getValue("2026-09-19").workMs)
    }

    @Test fun daysBeforeTheArchiveBeganAreNeitherWorkNorRest() {
        val cells = week(queries(seeded()), "2026-09-01")
        val beforeStart = cells.first { it.dayKey == "2026-09-02" }
        assertEquals(RecordsDayAppearance.REST, beforeStart.appearance)
        assertEquals(0L, beforeStart.workMs)
    }

    @Test fun aNightShiftPutsItsMorningOnTheNextDay() {
        val oneAm = ms("2026-09-15", 1)
        val shift = ScheduleRules.snapshot(ScheduleRuleInput(nights.scheduleHours()!!, oneAm, zone), SalarySettings("80", SalaryType.DAILY, 21.75, 0.0))
        assertEquals(ms("2026-09-14", 22), shift.startAtMs, 0.0)
        assertEquals(3 * 3_600_000.0, shift.elapsedMs, 0.0)
        assertEquals(5 * 3_600_000.0, shift.remainingMs, 0.0)
        assertEquals(1, shift.segments.size)
        val cells = week(queries(seeded(nights)), "2026-09-14")
        val byDay = cells.associateBy { it.dayKey }
        // Monday's shift starts 22:00, so Monday has 2 h; Tuesday gets Monday's 6 h plus its own 2 h.
        assertEquals(2 * 3_600_000L, byDay.getValue("2026-09-14").workMs)
        assertEquals(8 * 3_600_000L, byDay.getValue("2026-09-15").workMs)
        // Saturday receives Friday night's morning even though it is a rest day.
        assertEquals(6 * 3_600_000L, byDay.getValue("2026-09-19").workMs)
    }

    @Test fun observationsAndCorrectionsMarkTheirDays() {
        var state = seeded()
        state = state.copy(
            observations = state.observations + observation("2026-09-14", WorkObservationKind.COUNTDOWN_STARTED, 9),
            overrides = state.overrides + RecordTestFixtures.override("2026-09-15", DayOverrideKind.NOT_WORKING),
        )
        val byDay = week(queries(state), "2026-09-14").associateBy { it.dayKey }
        assertEquals(RecordsDayAppearance.RECORDED, byDay.getValue("2026-09-14").appearance)
        assertFalse(byDay.getValue("2026-09-14").isFromSavedSchedule)
        assertEquals(1, byDay.getValue("2026-09-14").observationCount)
        assertEquals(RecordsDayAppearance.CORRECTED, byDay.getValue("2026-09-15").appearance)
        assertEquals(0L, byDay.getValue("2026-09-15").workMs)
    }

    @Test fun declaredOvertimeStartsAtThePlannedEndNotAtTheDeclaration() {
        var state = seeded()
        val payload = FoundationCompat.base64(
            SessionCommands.overtimePayload(ms("2026-09-14", 20), ms("2026-09-14", 18)).toByteArray(Charsets.UTF_8),
        )
        state = state.copy(observations = state.observations + observation("2026-09-14", WorkObservationKind.OVERTIME_DECLARED, 16, payload))
        val monday = week(queries(state), "2026-09-14").first { it.dayKey == "2026-09-14" }
        assertEquals(2 * 3_600_000L, monday.overtimeMs)
        assertEquals(8 * 3_600_000L, monday.workMs)
    }

    @Test fun legacyOvertimeFallsBackToTheBaseScheduleWithoutOverlap() {
        val day = DayResolution(
            "2026-09-14", DayResolutionLayer.OVERRIDE, "p", "s", true, listOf(ShiftSegmentOf("2026-09-14", 9.0, 17.5)),
            baseScheduleIsWorkday = true, baseScheduleSegments = listOf(segment("2026-09-14", 9, 17)),
        )
        val legacy = FoundationCompat.base64("""{"overtimeEndAtMs":${ms("2026-09-14", 18).toLong()}}""".toByteArray())
        val segment = RecordsOvertime.declaredSegment(observation("2026-09-14", WorkObservationKind.OVERTIME_DECLARED, 16, legacy), day, avoidingRegularWork = true)!!
        assertEquals(ms("2026-09-14", 17, 30), segment.startAtMs, 0.0)
        assertEquals(ms("2026-09-14", 18), segment.endAtMs, 0.0)
        val quoted = FoundationCompat.base64("""{"overtimeEndAtMs":"${ms("2026-09-14", 18).toLong()}"}""".toByteArray())
        assertNull("a string is not a number", RecordsOvertime.declaredSegment(observation("2026-09-14", WorkObservationKind.OVERTIME_DECLARED, 16, quoted), day, true))
    }

    @Test fun withoutPlusOnlyTheLastSevenDaysAreRevealedAndNoSummaryIsBuilt() {
        val q = queries(seeded(), authorized = false)
        val (first, last) = q.window(RecordsScale.MONTH, LocalDate.parse("2026-09-16"))
        val days = q.displayDays(first.minusDays(1), last, now)
        val cells = q.cells(days, first, now).associateBy { it.dayKey }
        assertEquals(RecordsDayAppearance.LOCKED, cells.getValue("2026-09-09").appearance)
        assertEquals(0L, cells.getValue("2026-09-09").workMs)
        assertEquals(RecordsDayAppearance.RECORDED, cells.getValue("2026-09-10").appearance)
        assertEquals(RecordsDayAppearance.LOCKED, cells.getValue("2026-09-17").appearance)
        assertNull(q.headline(cells.values.toList(), days, now))
        assertTrue(q.dayCanvas("2026-09-09", now)!!.isLocked)
        assertTrue(q.dayCanvas("2026-09-09", now)!!.intervals.isEmpty())
        assertFalse(q.dayCanvas("2026-09-14", now)!!.isLocked)
        assertTrue("only Plus edits history", q.dayCanvas("2026-09-14", now)!!.editableShifts.isEmpty())

        val september21 = ms("2026-09-21", 10)
        val currentDays = q.displayDays(first.minusDays(1), last, september21)
        val currentCells = q.cells(currentDays, first, september21).associateBy { it.dayKey }
        assertEquals(RecordsDayAppearance.LOCKED, currentCells.getValue("2026-09-14").appearance)
        assertEquals(RecordsDayAppearance.RECORDED, currentCells.getValue("2026-09-15").appearance)
        assertEquals(RecordsDayAppearance.RECORDED, currentCells.getValue("2026-09-21").appearance)
        assertEquals(RecordsDayAppearance.LOCKED, currentCells.getValue("2026-09-22").appearance)
    }

    @Test fun theHeadlineCountsElapsedDaysAndKeepsSalaryOutUnlessShown() {
        val state = seeded()
        val salary = SalarySettings("22000", SalaryType.DAILY, 21.75, 0.0)
        for (shown in listOf(null, salary)) {
            val q = queries(state, salary = shown)
            val (first, last) = q.window(RecordsScale.WEEK, LocalDate.parse("2026-09-14"))
            val days = q.displayDays(first.minusDays(1), last, now)
            val headline = q.headline(q.cells(days, first, now), days, now)!!
            // Monday and Tuesday are past; today is still running.
            assertEquals(2, headline.completedScheduledWorkdays)
            assertEquals(7, headline.allocationDays)
            if (shown == null) {
                assertNull(headline.estimatedIncome)
                assertNull(headline.actualForecast?.total?.earnings)
            } else {
                assertEquals(44_000.0, headline.estimatedIncome!!, 0.001)
            }
        }
    }

    @Test fun thePastDayPageOffersItsOwnShiftForEditing() {
        val canvas = queries(seeded(nights)).dayCanvas("2026-09-15", now)!!
        assertEquals(listOf("2026-09-14", "2026-09-15"), canvas.editableShifts.map { it.anchorDayKey })
        assertEquals(8 * 3_600_000L, canvas.allocation.workMs)
        val future = queries(seeded()).dayCanvas("2026-09-18", now)!!
        assertTrue("a future day is changed through the schedule", future.editableShifts.isEmpty())
        assertEquals(RecordsDaySource.PLANNED, future.source)
    }

    @Test fun theLifeProfileProjectsEarlierYearsWithoutWritingThem() {
        val state = seeded().copy(lifeProfile = lifeProfile(workStarted = "2020-03-01"))
        val q = queries(state, currentHours = weekdays)
        val (first, last) = q.window(RecordsScale.WEEK, LocalDate.parse("2025-06-16"))
        val cells = q.cells(q.displayDays(first.minusDays(1), last, now), first, now)
        val monday = cells.first { it.dayKey == "2025-06-16" }
        assertTrue(monday.isProjection)
        assertEquals(8 * 3_600_000L, monday.workMs)
        assertEquals(RecordsDayAppearance.UNRECORDED, monday.appearance)
        assertFalse(cells.first { it.dayKey == "2025-06-21" }.isProjection && cells.first { it.dayKey == "2025-06-21" }.workMs > 0)
        // The same week without a profile has nothing, and the archive gained no rows either way.
        val bare = queries(seeded(), currentHours = weekdays)
        assertEquals(0L, bare.cells(bare.displayDays(first.minusDays(1), last, now), first, now).sumOf { it.workMs })
        assertEquals(1, state.periods.size)
        assertEquals(1, state.snapshots.size)
    }

    @Test fun lifeWalksTheWholeCareerThroughTheSameChain() {
        val state = seeded().copy(lifeProfile = lifeProfile(workStarted = "2020-03-01"))
        val model = queries(state, currentHours = weekdays).lifeModel(now, configuredMonthly = null)!!
        // 2020-03-01 to 2055-07-01 of weekday nine-to-six with lunch: about 35 years of 8-hour days.
        val years = model.allocation.workMs / (8 * 3_600_000.0 * 261)
        assertTrue("years of work: $years", years in 34.0..36.0)
        assertEquals(model.allocation.dayLengthMs, model.allocation.totalMs)
        assertTrue(model.cells.any { it.kind == LifeWeekKind.WORK_ESTIMATED })
        assertTrue(model.cells.any { it.kind == LifeWeekKind.WORK_PROJECTED })
        assertNull("no salary, no income", model.income)
    }

    @Test fun theRecordDayIndexFindsLeaveAndRestEntriesToo() {
        var state = seeded()
        state = state.copy(
            overrides = state.overrides + RecordTestFixtures.override("2026-09-10", DayOverrideKind.NOT_WORKING) +
                RecordTestFixtures.override("2026-09-11", DayOverrideKind.CLEARED),
            exceptions = state.exceptions + RecordTestFixtures.holiday("2026-09-12", CalendarEffect.WORK, CalendarExceptionOrigin.USER),
            observations = state.observations + observation("2026-09-08", WorkObservationKind.TIMER_SURFACE_FIRST_SEEN, 9),
        )
        val index = queries(state).recordDayIndex
        assertEquals(listOf("2026-09-12", "2026-09-10"), index.map { it.dayKey })
        assertNotNull(index.first().calendarException)
    }

    private fun lifeProfile(workStarted: String) = LifeProfile(
        LifeProfile.PROFILE_ID, 1995, null, 60, 7.5, false,
        PartialCivilDate(1995, null, null, CivilDatePrecision.YEAR), null,
        workStarted.split("-").map { it.toInt() }.let { (y, m, d) -> PartialCivilDate(y, m, d, CivilDatePrecision.DAY) },
        PartialCivilDate(2055, null, null, CivilDatePrecision.YEAR), 450, SleepSource.MANUAL, null,
        LifeWorkHistoryMode.ROUGH, null, emptyList(), null, 0.0, 1, LifeProfile.PROFILE_ID,
    )

    @Suppress("TestFunctionName")
    private fun ShiftSegmentOf(day: String, from: Double, to: Double) =
        com.rainif.doneat.core.domain.schedule.ShiftSegment(ms(day, 0) + from * 3_600_000, ms(day, 0) + to * 3_600_000)
}
