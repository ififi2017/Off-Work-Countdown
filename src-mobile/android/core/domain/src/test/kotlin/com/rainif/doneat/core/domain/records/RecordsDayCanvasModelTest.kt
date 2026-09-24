package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.ShiftSegment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * iOS `RecordsDayCanvasModelTests`: the day canvas is the only place a civil
 * day is cut out of the shifts that cross it, so these are the acceptance
 * tests for every records surface that prints a per-day number.
 */
class RecordsDayCanvasModelTest {
    private val hour = 3_600_000.0
    private val day = 1_787_529_600_000.0 // 2026-08-24T00:00Z
    private val next = day + 24 * hour

    private fun segment(start: Double, from: Double, to: Double) = ShiftSegment(start + from * hour, start + to * hour)

    private fun model(
        shifts: List<RecordsDayShift>,
        dayStart: Double = day,
        dayEnd: Double = dayStart + 24 * hour,
        dayKey: String = "2026-08-24",
        source: RecordsDaySource = RecordsDaySource.RECORDED,
        isToday: Boolean = false,
        nowMs: Double = 0.0,
        rulesFailed: Boolean = false,
    ) = RecordsDayCanvasModel.build(
        RecordsDayCanvasModel.Input(dayKey, dayStart, dayEnd, source, shifts, 8.0, isToday = isToday, nowMs = nowMs, rulesFailed = rulesFailed),
    )

    private fun ms(hours: Double) = (hours * hour).toLong()

    private val lunchShift = RecordsDayShift("2026-08-24", listOf(segment(day, 9.0, 12.0), segment(day, 13.0, 18.0)), source = RecordsDaySource.RECORDED)

    @Test fun aDayShiftItsLunchGapAndTheTimeAroundItNeverOverlap() {
        val canvas = model(listOf(lunchShift))
        assertEquals(ms(8.0), canvas.allocation.workMs)
        assertEquals(ms(1.0), canvas.allocation.breakMs)
        assertEquals(ms(8.0), canvas.allocation.sleepMs)
        assertEquals(ms(7.0), canvas.allocation.freeMs)
        assertEquals(canvas.allocation.dayLengthMs, canvas.allocation.totalMs)
        canvas.intervals.sortedBy { it.startAtMs }.zipWithNext().forEach { (a, b) -> assertTrue(a.endAtMs <= b.startAtMs) }
    }

    @Test fun ownWakingTimeIsBreaksPlusFreeTimeAndNotFreeTimeAlone() {
        val canvas = model(listOf(lunchShift))
        assertEquals(ms(7.0), canvas.allocation.freeMs)
        assertEquals(ms(8.0), canvas.wakingFreeMs)
        assertNotEquals(canvas.allocation.freeMs, canvas.wakingFreeMs)
    }

    @Test fun anOvernightShiftShowsItsRealIntersectionWithEachCivilDay() {
        val shift = RecordsDayShift("2026-08-24", listOf(segment(day, 20.0, 28.0)), source = RecordsDaySource.RECORDED)
        val first = model(listOf(shift))
        val second = model(listOf(shift), dayStart = next, dayKey = "2026-08-25", source = RecordsDaySource.REST)
        assertEquals(ms(4.0), first.allocation.workMs)
        assertEquals(ms(4.0), second.allocation.workMs)
        assertEquals(second.allocation.dayLengthMs, second.allocation.totalMs)
        assertEquals(RecordsDaySource.RECORDED, second.source)
        assertTrue(second.workIntervals.all { it.anchorDayKey == "2026-08-24" })
    }

    @Test fun twoShiftsTouchingOneDayAreBothDrawnAndBothEditable() {
        val previous = RecordsDayShift("2026-08-23", listOf(segment(day, -4.0, 6.0)), source = RecordsDaySource.RECORDED, isEditable = true)
        val own = RecordsDayShift("2026-08-24", listOf(segment(day, 20.0, 28.0)), source = RecordsDaySource.CORRECTED, isEditable = true)
        val canvas = model(listOf(own, previous))
        assertEquals(ms(10.0), canvas.allocation.workMs)
        assertEquals(listOf("2026-08-23", "2026-08-24"), canvas.editableShifts.map { it.anchorDayKey })
        val earlier = canvas.editableShifts.first()
        assertEquals(10 * hour, earlier.endAtMs - earlier.startAtMs, 0.0)
        assertTrue(earlier.hasHours)
        assertEquals("2026-08-23", canvas.workIntervals.first().anchorDayKey)
        assertEquals(RecordsDaySource.CORRECTED, canvas.workIntervals.last().source)
    }

    @Test fun sixteenHoursBetweenTwoNightShiftsIsNotALunchBreak() {
        val previous = RecordsDayShift("2026-08-23", listOf(segment(day, -4.0, 4.0)), source = RecordsDaySource.RECORDED)
        val own = RecordsDayShift("2026-08-24", listOf(segment(day, 20.0, 28.0)), source = RecordsDaySource.RECORDED)
        val canvas = model(listOf(previous, own))
        assertEquals(0L, canvas.allocation.breakMs)
        assertEquals(ms(8.0), canvas.allocation.workMs)
    }

    @Test fun declaredOvertimeAndRegularWorkAreDrawnOnce() {
        val shift = RecordsDayShift("2026-08-24", listOf(segment(day, 9.0, 18.0)), listOf(segment(day, 17.0, 20.0)), RecordsDaySource.RECORDED)
        val canvas = model(listOf(shift))
        assertEquals(ms(9.0), canvas.allocation.workMs)
        assertEquals(ms(2.0), canvas.allocation.overtimeMs)
        assertEquals(canvas.allocation.dayLengthMs, canvas.allocation.totalMs)
    }

    @Test fun shortAndLongDaysSumToTheirRealLength() {
        val shift = RecordsDayShift("2026-08-24", listOf(segment(day, 9.0, 18.0)), source = RecordsDaySource.RECORDED)
        val short = model(listOf(shift), dayEnd = day + 23 * hour)
        val long = model(listOf(shift), dayEnd = day + 25 * hour)
        assertEquals(ms(23.0), short.allocation.dayLengthMs)
        assertEquals(short.allocation.dayLengthMs, short.allocation.totalMs)
        assertEquals(ms(25.0), long.allocation.dayLengthMs)
        assertEquals(long.allocation.dayLengthMs, long.allocation.totalMs)
        assertTrue((short.intervals + long.intervals).all { it.durationMs >= 0 })
        assertTrue(short.wakingFreeShare in 0.0..1.0 && long.wakingFreeShare in 0.0..1.0)
    }

    @Test fun aFailedExpansionLeavesTheDayUnclassifiedInsteadOfPaddingIt() {
        val complete = model(emptyList())
        val incomplete = model(emptyList(), rulesFailed = true)
        assertEquals(0L, complete.allocation.unclassifiedMs)
        assertEquals(ms(16.0), complete.allocation.freeMs)
        assertEquals(0L, incomplete.allocation.freeMs)
        assertEquals(ms(16.0), incomplete.allocation.unclassifiedMs)
        assertEquals(incomplete.allocation.dayLengthMs, incomplete.allocation.totalMs)
        assertTrue(incomplete.hasIncompleteRules)
    }

    @Test fun sleepGoesInTheLongestNonWorkStretchAndNeverOverWork() {
        val night = RecordsDayShift("2026-08-24", listOf(segment(day, 0.0, 6.0)), source = RecordsDaySource.RECORDED)
        val sleep = model(listOf(night)).intervals.filter { it.kind == TimeAllocationKind.SLEEP }
        assertEquals(1, sleep.size)
        assertEquals(day + 6 * hour, sleep[0].startAtMs, 0.0)
        assertEquals(RecordsDaySource.SLEEP_ESTIMATE, sleep[0].source)
        assertNull(sleep[0].anchorDayKey)
    }

    @Test fun theNowLineOnlyExistsTodayAndLandsOnAWholeMinute() {
        val now = day + 14 * hour + 32 * 60_000 + 47_000
        val shift = RecordsDayShift("2026-08-24", listOf(segment(day, 9.0, 18.0)), source = RecordsDaySource.RECORDED)
        val today = model(listOf(shift), isToday = true, nowMs = now)
        val past = model(listOf(shift), isToday = false, nowMs = now)
        assertNull(past.nowAtMs)
        assertNull(past.projectionStartsAtMs)
        val expected = day + (14 * 60 + 32) * 60_000.0
        assertEquals(expected, today.nowAtMs!!, 0.0)
        assertEquals(expected, today.projectionStartsAtMs!!, 0.0)
        assertEquals(2, today.workIntervals.size)
        assertEquals(expected, today.workIntervals[0].endAtMs, 0.0)
        assertEquals(RecordsDaySource.RECORDED, today.workIntervals[0].source)
        assertEquals(expected, today.workIntervals[1].startAtMs, 0.0)
        assertEquals(RecordsDaySource.AFTER_NOW, today.workIntervals[1].source)
    }

    @Test fun aLockedDayCarriesNothingReal() {
        val canvas = RecordsDayCanvasModel.locked("2026-08-24", day, next)
        assertTrue(canvas.isLocked)
        assertTrue(canvas.intervals.isEmpty())
        assertTrue(canvas.editableShifts.isEmpty())
        assertEquals(0L, canvas.allocation.totalMs)
        assertEquals(0L, canvas.allocation.dayLengthMs)
        assertEquals(RecordsDaySource.LOCKED, canvas.source)
    }

    @Test fun aRestDayIsStillEditableAndNamedByItsDate() {
        val empty = RecordsDayShift("2026-08-24", emptyList(), source = RecordsDaySource.REST, isEditable = true)
        val canvas = model(listOf(empty), source = RecordsDaySource.REST)
        assertEquals(listOf("2026-08-24"), canvas.editableShifts.map { it.anchorDayKey })
        assertFalse(canvas.editableShifts.first().hasHours)
        assertEquals(0L, canvas.allocation.workMs)
    }

    @Test fun aPlanOrProjectionNeverOffersAnEditEntry() {
        val planned = RecordsDayShift("2026-08-24", listOf(segment(day, 9.0, 18.0)), source = RecordsDaySource.PLANNED)
        val canvas = model(listOf(planned), source = RecordsDaySource.PLANNED)
        assertTrue(canvas.editableShifts.isEmpty())
        assertTrue(canvas.workIntervals.all { it.source == RecordsDaySource.PLANNED })
        assertTrue(canvas.source.isEstimated)
    }

    @Test fun estimatesAreMarkedAsEstimatesNotFaded() {
        assertFalse(RecordsDaySource.RECORDED.isEstimated)
        assertFalse(RecordsDaySource.CORRECTED.isEstimated)
        assertTrue(RecordsDaySource.CORRECTED.isCorrection)
        listOf(
            RecordsDaySource.SCHEDULE_ESTIMATE, RecordsDaySource.AFTER_NOW, RecordsDaySource.LIFE_PROJECTION,
            RecordsDaySource.PLANNED, RecordsDaySource.SLEEP_ESTIMATE,
        ).forEach { assertTrue(it.name, it.isEstimated) }
    }

    @Test fun overtimeStrengthUsesAFixedDailyScaleAndNeverDarkensEstimates() {
        val strengths = listOf(0L, 1, 2, 4, 8).map { RecordsWorkIntensity.opacity(it * 3_600_000, estimated = false) }
        assertTrue(strengths.zipWithNext().all { (a, b) -> a < b })
        assertEquals(strengths.last(), RecordsWorkIntensity.opacity(12 * 3_600_000, estimated = false), 0.0)
        assertTrue(RecordsWorkIntensity.opacity(8 * 3_600_000, estimated = true) < strengths.first())
    }
}
