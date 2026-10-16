package com.rainif.doneat.core.domain.records

import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class Records322PresentationTest {
    private fun cell(appearance: RecordsDayAppearance = RecordsDayAppearance.RECORDED) = RecordsDayCell(
        "2026-10-16", LocalDate.parse("2026-10-16"), appearance, 8 * 3_600_000L, 3_600_000, 0, 0, 1, false, false, false, false,
    )

    @Test fun actualAndPlannedUseTheSameVocabularyAtEveryScale() {
        assertTrue(RecordsDayLook(cell()).hasSolidHours)
        assertTrue(RecordsDayLook(cell().copy(isFromSavedSchedule = true)).hasSolidHours)
        assertFalse(RecordsDayLook(cell().copy(isToday = true, isFromSavedSchedule = true)).hasSolidHours)
        assertTrue(RecordsDayLook(cell().copy(isToday = true, isFromSavedSchedule = true)).isEstimated)
        assertTrue(RecordsDayLook(cell(RecordsDayAppearance.PLANNED).copy(isFuture = true)).isEstimated)
        assertTrue(RecordsDayLook(cell(RecordsDayAppearance.CORRECTED)).hasSolidHours)
        assertTrue(RecordsDayLook(cell(RecordsDayAppearance.UNRECORDED).copy(isProjection = true)).isEstimated)
    }

    @Test fun lockedAppearanceCannotRevealEvenAccidentallyPopulatedHoursOrConflict() {
        val look = RecordsDayLook(cell(RecordsDayAppearance.LOCKED).copy(isFuture = true, isProjection = true, hasConflict = true))
        assertEquals(0L, look.totalMs)
        assertFalse(look.hasHours)
        assertFalse(look.hasSolidHours)
        assertFalse(look.isEstimated)
        assertFalse(look.hasConflict)
        assertFalse(look.isUnrecordedWorkday)
    }

    @Test fun holidayNamesSpanOnlyContiguousUnlockedDatesInOneWeek() {
        assertEquals(listOf(RecordsHolidayRun(1, 3, "Holiday"), RecordsHolidayRun(5, 1, "Holiday")),
            recordsHolidayRuns(listOf(null, "Holiday", "Holiday", "Holiday", null, "Holiday", "")))
    }

    @Test fun lifeHasOneCellPerCivilYearAndOpenEndedRetirement() {
        val zone = ZoneId.of("Europe/Berlin")
        val birth = LifeDates.ms(LocalDate.parse("1990-06-15"), zone)
        val now = LifeDates.ms(LocalDate.parse("2026-06-14"), zone)
        val retire = LifeDates.ms(LocalDate.parse("2050-06-15"), zone)
        val stages = listOf(LifeStageSpan(LifeStageKind.WORK, birth, retire, CivilDatePrecision.DAY, CivilDatePrecision.DAY),
            LifeStageSpan(LifeStageKind.RETIREMENT, retire, null, CivilDatePrecision.DAY, null))
        val years = recordsLifeYears(stages, birth to retire, now, zone)
        assertEquals(80, years.size)
        assertEquals(35, years.single { it.isCurrent }.age)
        assertTrue(years.take(35).all { it.isPast })
        assertEquals(LifeStageKind.RETIREMENT, years[60].stage?.kind)
        assertEquals(2069, years.last().year)
        assertEquals(36, recordsLifeYears(stages, birth to retire, LifeDates.ms(LocalDate.parse("2026-06-15"), zone), zone).single { it.isCurrent }.age)
    }

    @Test fun currentYearRemainsSelectableAtAndAfterEveryDecadeBoundary() {
        val zone = ZoneId.of("Pacific/Auckland")
        val birthDay = LocalDate.parse("1946-10-16")
        val birth = LifeDates.ms(birthDay, zone)
        val retire = LifeDates.ms(birthDay.plusYears(65), zone)
        val stages = listOf(
            LifeStageSpan(LifeStageKind.WORK, birth, retire, CivilDatePrecision.DAY, CivilDatePrecision.DAY),
            LifeStageSpan(LifeStageKind.RETIREMENT, retire, null, CivilDatePrecision.DAY, null),
        )
        for (boundary in listOf(80, 90, 100)) {
            val birthday = birthDay.plusYears(boundary.toLong())
            for (offset in listOf(-1L, 0L, 1L)) {
                val now = LifeDates.ms(birthday.plusDays(offset), zone)
                // timelineBounds ends at today once retirement has begun.
                val bounds = LifeStageCalculator.timelineBounds(stages, now)!!
                val years = recordsLifeYears(stages, bounds, now, zone)
                val current = years.single { it.isCurrent }
                assertEquals(if (offset < 0) boundary - 1 else boundary, current.age)
                assertEquals(LifeStageKind.RETIREMENT, current.stage?.kind)
                assertFalse(current.isPast)
                assertTrue(years.last().age >= current.age)
                assertEquals(if (offset < 0) boundary else boundary + 10, years.size)
                assertTrue(years.take(current.age).all { it.isPast })
            }
        }
    }

    @Test fun weekConclusionCountsSolidDaysAndKeepsTheMissingDayAction() {
        val actual = cell().copy(dayKey = "2026-10-15", date = LocalDate.parse("2026-10-15"))
        val today = cell().copy(isToday = true, isFromSavedSchedule = true)
        val empty = cell(RecordsDayAppearance.UNRECORDED).copy(dayKey = "2026-10-14", date = LocalDate.parse("2026-10-14"), workMs = 0, overtimeMs = 0)
        val summary = RecordsHeadlineSummary(2, 8 * 3_600_000L, 3_600_000, 0, null, 2, 0, TimeAllocationShare.ZERO, false, null)
        val metrics = recordsInsightMetrics(summary, listOf(empty, actual, today), RecordsScale.WEEK)
        assertEquals(1, metrics.recordedDays)
        assertEquals(2, metrics.completedWorkdays)
        assertEquals(LocalDate.parse("2026-10-14"), metrics.emptyDay)
        assertEquals(9 * 3_600_000.0, metrics.workedMs, 0.0)
        assertEquals(.25, metrics.extraWorkdays, 0.0)
    }
}
