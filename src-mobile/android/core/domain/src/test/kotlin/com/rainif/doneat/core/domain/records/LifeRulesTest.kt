package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.DayOfWeek
import java.time.ZoneId

/** iOS `LifeViewCalculatorTests`, restated against the Kotlin rules, plus the profile write. */
class LifeRulesTest {
    private val zone: ZoneId = ZoneId.of("UTC")
    private val hour = 3_600_000.0
    private var ids = 0
    private fun newId() = "00000000-0000-4000-8000-%012d".format(++ids)

    private fun ms(year: Int, month: Int, day: Int) = LifeDates.ms(LocalDate.of(year, month, day), zone)
    private fun exact(year: Int, month: Int, day: Int) = LifeDates.exact(year, month, day)!!

    private fun profile(
        bornOn: PartialCivilDate?,
        workStarted: PartialCivilDate?,
        retirementOn: PartialCivilDate?,
        sleepHours: Double? = 8.0,
        mode: LifeWorkHistoryMode = LifeWorkHistoryMode.ROUGH,
        roughSalary: LifeSalary? = null,
        periods: List<LifeEmploymentPeriod> = emptyList(),
        decline: LifeIncomeDecline? = null,
    ) = LifeProfiles.blank(0.0, ::newId).copy(
        bornOn = bornOn, workStartedPartial = workStarted, retirementOn = retirementOn, averageSleepHours = sleepHours,
        workHistoryMode = mode, roughCurrentSalary = roughSalary, employmentPeriods = periods, futureIncomeDecline = decline,
    )

    private fun day(date: LocalDate, startHour: Int, hours: Int, overtimeHours: Int = 0, isOverride: Boolean = false, periodID: String = "P"): LifeScheduleDay {
        val start = LifeDates.ms(date, zone) + startHour * hour
        val end = start + hours * hour
        return LifeScheduleDay(
            periodID, FoundationCompat.dayKey(date), LifeDates.ms(date, zone), listOf(ShiftSegment(start, end)),
            if (overtimeHours > 0) listOf(ShiftSegment(end, end + overtimeHours * hour)) else emptyList(), isOverride,
        )
    }

    @Test fun fifteenThousandDayLifeWithTenYearsOfRecordsBuildsOnTheJvm() {
        val first = LocalDate.of(1980, 1, 1)
        val last = first.plusDays(15_000)
        val workStart = last.minusYears(10)
        val profile = profile(
            LifeDates.exact(first.year, first.monthValue, first.dayOfMonth),
            LifeDates.exact(workStart.year, workStart.monthValue, workStart.dayOfMonth),
            LifeDates.exact(last.year, last.monthValue, last.dayOfMonth),
        )
        val days = (0 until java.time.temporal.ChronoUnit.DAYS.between(workStart, last).toInt())
            .map { workStart.plusDays(it.toLong()) }
            .filter { it.dayOfWeek != DayOfWeek.SATURDAY && it.dayOfWeek != DayOfWeek.SUNDAY }
            .map { day(it, 9, 8) }
        val before = System.nanoTime()
        val model = LifeViewCalculator.build(profile, days, emptySet(), ms(2016, 1, 1), zone)
        val elapsedMs = (System.nanoTime() - before) / 1_000_000.0
        println("QA-056 JVM LifeViewCalculator: 15,000 civil days, ${days.size} workdays, $elapsedMs ms")
        assertEquals(2_143, model.cells.size)
        assertTrue(model.workedWeeks > 0)
        assertTrue(model.remainingWeeks > 0)
        assertTrue(model.workShare.isFinite())
    }

    @Test fun weeksRunToRetirementNotAFixedYear() {
        val p = profile(LifeDates.yearOnly(1990), exact(2012, 1, 1), LifeDates.yearOnly(2050))
        val model = LifeViewCalculator.build(
            p, listOf(day(LocalDate.of(2026, 8, 24), 9, 8), day(LocalDate.of(2030, 8, 26), 9, 8)), emptySet(), ms(2026, 8, 30), zone,
        )
        assertTrue(model.cells.isNotEmpty())
        assertTrue(model.cells.any { it.kind == LifeWeekKind.WORK_ESTIMATED || it.kind == LifeWeekKind.WORK_PROJECTED })
        assertEquals(2050, model.cells.last().year)
    }

    @Test fun endedPeriodsLeaveARealGap() {
        val p = profile(exact(2026, 1, 1), exact(2026, 1, 1), exact(2026, 1, 22))
        val days = listOf(
            day(LocalDate.of(2026, 1, 1), 9, 4, periodID = "A"), day(LocalDate.of(2026, 1, 2), 9, 4, periodID = "A"),
            day(LocalDate.of(2026, 1, 15), 9, 8, periodID = "B"), day(LocalDate.of(2026, 1, 16), 9, 8, periodID = "B"),
        )
        val model = LifeViewCalculator.build(p, days, emptySet(), ms(2026, 1, 10), zone)
        assertEquals(listOf(LifeWeekKind.WORK_ESTIMATED, LifeWeekKind.NONE, LifeWeekKind.WORK_PROJECTED), model.cells.map { it.kind })
        assertEquals(24.0 / (21 * 24), model.workShare, 1e-7)
        assertEquals((21 * 16.0 - 24) / (21 * 24), model.ownAwakeShare, 1e-7)
    }

    @Test fun detailedEmploymentRemovesScheduledWorkFromGaps() {
        val salary = LifeSalary(10_000.0, LifeSalaryCadence.MONTHLY)
        val p = profile(
            exact(2026, 1, 1), exact(2026, 1, 1), exact(2026, 1, 29), mode = LifeWorkHistoryMode.DETAILED, roughSalary = salary,
            periods = listOf(
                LifeEmploymentPeriod("A", exact(2026, 1, 1), exact(2026, 1, 8), salary),
                LifeEmploymentPeriod("B", exact(2026, 1, 15), exact(2026, 1, 22), salary),
            ),
        )
        val now = ms(2026, 1, 25)
        val days = listOf(2, 10, 16, 23, 26).map { day(LocalDate.of(2026, 1, it), 9, 8) }
        val model = LifeViewCalculator.build(p, days, emptySet(), now, zone)
        assertEquals(
            listOf(LifeWeekKind.WORK_ESTIMATED, LifeWeekKind.NONE, LifeWeekKind.WORK_ESTIMATED, LifeWeekKind.WORK_PROJECTED),
            model.cells.map { it.kind },
        )
        assertEquals((3 * 8 * hour).toLong(), model.allocation.workMs)
        val stages = LifeStageCalculator.stages(p, zone, now)
        assertEquals(LifeStageKind.UNSET, LifeStageCalculator.kindAt(ms(2026, 1, 10), stages))
        assertEquals(LifeStageKind.WORK, LifeStageCalculator.kindAt(ms(2026, 1, 16), stages))
        assertEquals(LifeStageKind.UNSET, LifeStageCalculator.kindAt(ms(2026, 1, 23), stages))
        assertEquals(LifeStageKind.WORK, LifeStageCalculator.kindAt(ms(2026, 1, 26), stages))
    }

    @Test fun effectiveSegmentLengthsDecideTheWorkShare() {
        val p = profile(exact(2026, 1, 1), exact(2026, 1, 1), exact(2026, 1, 8))
        val date = LocalDate.of(2026, 1, 2)
        val now = ms(2026, 1, 4)
        // The four-hour day is supplied twice: the union must not count it twice.
        val short = LifeViewCalculator.build(p, listOf(day(date, 9, 4), day(date, 9, 4)), emptySet(), now, zone)
        val long = LifeViewCalculator.build(p, listOf(day(date, 9, 8)), emptySet(), now, zone)
        assertEquals(4.0 / (7 * 24), short.workShare, 1e-7)
        assertEquals(8.0 / (7 * 24), long.workShare, 1e-7)
        assertTrue(long.ownAwakeShare < short.ownAwakeShare)
    }

    @Test fun recordedOvertimeStaysWork() {
        val p = profile(exact(2026, 1, 1), exact(2026, 1, 1), exact(2026, 1, 2))
        val model = LifeViewCalculator.build(p, listOf(day(LocalDate.of(2026, 1, 1), 9, 8, overtimeHours = 2)), emptySet(), ms(2026, 1, 2), zone)
        assertEquals((8 * hour).toLong(), model.allocation.workMs)
        assertEquals((2 * hour).toLong(), model.allocation.overtimeMs)
        assertEquals(10.0 / 24, model.workShare, 1e-7)
        assertEquals(6.0 / 24, model.ownAwakeShare, 1e-7)
    }

    @Test fun leaveIsNotWorkAndACorrectionStaysVisible() {
        val p = profile(exact(2026, 1, 1), exact(2026, 1, 1), exact(2026, 1, 15))
        val leave = (8..14).map { LifeScheduleDay("P", "2026-01-%02d".format(it), ms(2026, 1, it), emptyList(), isOverride = false) }
        val model = LifeViewCalculator.build(
            p, listOf(day(LocalDate.of(2026, 1, 3), 10, 9, isOverride = true)) + leave, setOf(leave[2].dayKey), ms(2026, 1, 15), zone,
        )
        assertEquals(listOf(LifeWeekKind.WORK_OVERRIDE, LifeWeekKind.NONE), model.cells.map { it.kind })
        assertTrue(model.cells[1].outsidePeriodTimeZone)
    }

    @Test fun yearOnlyDatesUseMidYear() {
        assertEquals(LocalDate.of(1990, 7, 1), LifeDates.anchor(LifeDates.yearOnly(1990)))
        assertNull(LifeDates.exact(2026, 13, 1))
        assertNull(LifeDates.exact(2026, 2, 31))
    }

    @Test fun stagesStopAtRetirementAndInventNoLifespan() {
        val p = RecordJson.migrateLegacyFields(
            LifeProfiles.blank(0.0, ::newId).copy(birthYear = 1990, retirementAge = 60, workStartedPartial = LifeDates.yearOnly(2012)),
        )
        val now = 1_787_529_600_000.0
        val stages = LifeStageCalculator.stages(p, zone, now)
        assertTrue(stages.any { it.kind == LifeStageKind.WORK && it.startMs != null && it.endMs != null })
        val bounds = LifeStageCalculator.timelineBounds(stages, now)!!
        assertEquals(2050, java.time.Instant.ofEpochMilli(bounds.second.toLong()).atZone(zone).year)
        val buckets = LifeStageCalculator.buckets(stages, bounds.first, bounds.second, 20, now)
        assertEquals(20, buckets.size)
        assertTrue(buckets.any { it.kind == LifeStageKind.CHILDHOOD })
        assertTrue(buckets.any { it.kind == LifeStageKind.WORK })
    }

    @Test fun theCurrentStageFollowsEveryBoundary() {
        val stages = listOf(
            LifeStageSpan(LifeStageKind.CHILDHOOD, ms(2010, 1, 1), ms(2022, 9, 1), CivilDatePrecision.DAY, CivilDatePrecision.DAY),
            LifeStageSpan(LifeStageKind.STUDY, ms(2022, 9, 1), ms(2030, 7, 1), CivilDatePrecision.DAY, CivilDatePrecision.DAY),
            LifeStageSpan(LifeStageKind.WORK, ms(2030, 7, 1), ms(2070, 1, 1), CivilDatePrecision.DAY, CivilDatePrecision.DAY),
            LifeStageSpan(LifeStageKind.RETIREMENT, ms(2070, 1, 1), null, CivilDatePrecision.DAY, null),
        )
        assertEquals(LifeStageKind.CHILDHOOD, LifeStageCalculator.kindAt(ms(2018, 1, 1), stages))
        assertEquals(LifeStageKind.STUDY, LifeStageCalculator.kindAt(ms(2026, 8, 31), stages))
        assertEquals(LifeStageKind.WORK, LifeStageCalculator.kindAt(ms(2040, 1, 1), stages))
        assertEquals(LifeStageKind.RETIREMENT, LifeStageCalculator.kindAt(ms(2075, 1, 1), stages))
    }

    @Test fun progressIsClamped() {
        assertEquals(0.0, LifeStageCalculator.progress(1_000.0, 2_000.0, 0.0), 0.0)
        assertEquals(0.5, LifeStageCalculator.progress(1_000.0, 2_000.0, 1_500.0), 0.0)
        assertEquals(1.0, LifeStageCalculator.progress(1_000.0, 2_000.0, 3_000.0), 0.0)
    }

    @Test fun theCareerSplitsAtNowWithoutChangingItsIdentity() {
        val work = LifeStageSpan(LifeStageKind.WORK, ms(2012, 7, 1), ms(2050, 7, 1), CivilDatePrecision.YEAR, CivilDatePrecision.YEAR)
        val split = LifeStageCalculator.canvasStages(listOf(work), ms(2026, 9, 1))
        assertEquals(listOf(LifeWorkPeriod.ELAPSED, LifeWorkPeriod.FUTURE), split.map { it.workPeriod })
        assertEquals(ms(2026, 9, 1), split[0].endMs!!, 0.0)
        assertEquals(ms(2026, 9, 1), split[1].startMs!!, 0.0)
        val later = LifeStageCalculator.canvasStages(listOf(work), ms(2027, 3, 1))
        assertEquals(split.map { it.id }, later.map { it.id })
    }

    private fun lifeIncome(p: LifeProfile, now: Double) =
        RecordsQueries(RecordState(lifeProfile = p), HolidayCalendar.EMPTY, zone, authorized = true).lifeModel(now, configuredMonthly = null)?.income

    @Test fun aFutureRoughWorkYearDelaysIncomeUntilWorkBegins() {
        val p = profile(
            LifeDates.yearOnly(2008), LifeDates.yearOnly(2030), LifeDates.yearOnly(2068),
            roughSalary = LifeSalary(120_000.0, LifeSalaryCadence.YEARLY),
        ).copy(birthYear = 2008)
        val income = lifeIncome(p, ms(2026, 1, 1))!!
        assertEquals(0.0, income.historicalGross, 0.0)
        assertEquals(4_560_000.0, income.projectedGross, 0.001)
    }

    @Test fun aPassedAdjustmentAgeAppliesTheRatioAndLeavesHistory() {
        val now = ms(2036, 1, 1)
        val base = profile(
            LifeDates.yearOnly(1990), LifeDates.yearOnly(2020), LifeDates.yearOnly(2050),
            roughSalary = LifeSalary(10_000.0, LifeSalaryCadence.MONTHLY),
        )
        val level = lifeIncome(base, now)!!
        val declining = lifeIncome(base.copy(futureIncomeDecline = LifeIncomeDecline(45, 0.6)), now)!!
        assertEquals(level.historicalGross, declining.historicalGross, 0.0)
        assertTrue(declining.projectedGross < level.projectedGross)
        assertEquals(0.6, declining.projectedGross / level.projectedGross, 0.001)
    }

    @Test fun aProfileEditIsStampedOnceAndSameContentWritesNothing() {
        val first = LifeProfiles.edit(RecordState(), 10.0, ::newId) { it.copy(bornOn = LifeDates.yearOnly(1990), averageSleepHours = 7.5, sleepSource = SleepSource.MANUAL) }
        val profile = first.lifeProfile!!
        assertEquals(1, profile.editCount)
        assertEquals(450, profile.averageSleepMinutes)
        assertEquals(10.0, profile.sleepSourceUpdatedAtMs!!, 0.0)
        assertSame(first, LifeProfiles.edit(first, 20.0, ::newId) { it })
        val second = LifeProfiles.edit(first, 30.0, ::newId) { it.copy(retirementOn = LifeDates.yearOnly(2055)) }
        assertEquals(2, second.lifeProfile!!.editCount)
        // Another field changing leaves the sleep provenance where it was.
        assertEquals(10.0, second.lifeProfile!!.sleepSourceUpdatedAtMs!!, 0.0)
        val erased = RecordState(erased = listOf(ErasedID(RecordEntityType.LIFE_PROFILE, LifeProfile.PROFILE_ID, 0.0, editCount = 7)))
        val revived = LifeProfiles.edit(erased, 40.0, ::newId) { it.copy(bornOn = LifeDates.yearOnly(1990)) }
        assertEquals(8, revived.lifeProfile!!.editCount)
        assertTrue(revived.erased.isEmpty())
        assertNotNull(revived.lifeProfile)
        assertFalse(revived.isErased(RecordEntityType.LIFE_PROFILE, LifeProfile.PROFILE_ID))
    }
}
