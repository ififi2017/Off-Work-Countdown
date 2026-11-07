package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.records.RecordTestFixtures.ms
import com.rainif.doneat.core.domain.schedule.CountedOvertime
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

/** iOS `OvertimeStartTests.recordsEditing` and `recordsDeclaration`, against the pure functions. */
class RecordOvertimeStateTest {
    private val zone = ZoneId.of(RecordTestFixtures.ZONE)
    private val hours = SnapshotHours("09:00", "17:00", listOf(1, 2, 3, 4, 5), "classic", breakStartTime = null, breakDurationMinutes = 0)
    private val day = "2026-09-07"
    private var ids = 0
    private fun context(nowMs: Double, canEdit: Boolean = true) = RecordEditContext(
        nowMs = nowMs, recordsTimeZone = RecordTestFixtures.ZONE, canEdit = canEdit, holidays = HolidayCalendar.EMPTY,
        currentHours = { hours }, newId = { "00000000-0000-4000-8000-%012d".format(++ids) },
    )
    private fun queries(state: RecordState) = RecordsQueries(state, HolidayCalendar.EMPTY, zone, true, currentHours = hours)

    @Test fun countedHoursStepInQuarterHoursAndThePeriodKeepsItsEndAfterMidnight() {
        var state = RecordOvertimeState(false, 1_000_000.0, 1_000_000.0 + 3_600_000, null, 1.0, null, null)
        assertEquals(4_500_000.0, state.steppedCountedMs(1), 0.0)
        assertEquals(2_700_000.0, state.steppedCountedMs(-1), 0.0)
        state = state.copy(countedMs = 0.0)
        assertEquals(0.0, state.steppedCountedMs(-1), 0.0)
        state = state.copy(countedMs = CountedOvertime.MAXIMUM_MS)
        assertEquals(CountedOvertime.MAXIMUM_MS, state.steppedCountedMs(1), 0.0)

        val evening = ms("2026-08-31", 22)
        var late = RecordOvertimeState(false, evening, evening + 3_600_000, null, 1.0, null, null)
        late = late.withEnd(60, zone)
        assertEquals(3 * 3_600_000.0, late.measuredMs, 0.0)
        late = late.withEnd(23 * 60, zone)
        assertEquals(3_600_000.0, late.measuredMs, 0.0)
        // Moving the start keeps the end's clock time after it.
        late = late.withStart(21 * 60, zone)
        assertEquals(2 * 3_600_000.0, late.measuredMs, 0.0)
    }

    @Test fun aDeclarationReplacesTheDaysPeriodCountedHoursAndPay() {
        val now = ms(day, 23)
        val seeded = RecordEdits.ensureSeeded(RecordState(), hours, context(now))

        var state = RecordOvertimeState.load(day, queries(seeded), defaultMultiplier = 1.0)
        assertFalse(state.hasDeclaration)
        assertEquals(ms(day, 17), state.startAtMs, 0.0)

        // 18:00 to 21:00 is three hours; the person counts two and a half at 1.5×.
        state = state.withStart(18 * 60, zone).withEnd(21 * 60, zone)
        assertEquals(3 * 3_600_000.0, state.measuredMs, 0.0)
        state = state.copy(countedMs = 2.5 * 3_600_000, payMultiplier = 1.5)
        val (written, ok) = RecordEdits.declareOvertime(seeded, day, state, context(now), capturesObservations = true)
        assertTrue(ok)

        val reloaded = RecordOvertimeState.load(day, queries(written), defaultMultiplier = 1.0)
        assertTrue(reloaded.hasDeclaration)
        assertEquals(state.startAtMs, reloaded.startAtMs, 0.0)
        assertEquals(state.endAtMs, reloaded.endAtMs, 0.0)
        assertEquals(2.5 * 3_600_000, reloaded.countedMs!!, 0.0)
        assertEquals(1.5, reloaded.payMultiplier, 0.0)
        val resolution = queries(written).resolvedDays(java.time.LocalDate.parse(day), java.time.LocalDate.parse(day)).single()
        assertEquals(2.5 / 3, queries(written).overtimeCountScale(resolution), 1e-12)

        // The next declaration for the day wins; earlier ones stay.
        val again = reloaded.copy(countedMs = null).withEnd(20 * 60, zone)
        val (second, secondOk) = RecordEdits.declareOvertime(written, day, again, context(now + 60_000), capturesObservations = true)
        assertTrue(secondOk)
        val last = RecordOvertimeState.load(day, queries(second), defaultMultiplier = 1.0)
        assertNull(last.countedMs)
        assertEquals(2 * 3_600_000.0, last.measuredMs, 0.0)
        assertEquals(2, second.observations.count { it.kind == WorkObservationKind.OVERTIME_DECLARED })
    }

    @Test fun aDayWithoutOvertimeStartsAtTheDefaultMultiplier() {
        val seeded = RecordEdits.ensureSeeded(RecordState(), hours, context(ms(day, 10)))
        assertEquals(0.0, RecordOvertimeState.load(day, queries(seeded), defaultMultiplier = 0.0).payMultiplier, 0.0)
        assertEquals(2.0, RecordOvertimeState.load(day, queries(seeded), defaultMultiplier = 2.0).payMultiplier, 0.0)
    }

    @Test fun refusedDeclarationsLeaveTheArchiveUntouched() {
        val seeded = RecordEdits.ensureSeeded(RecordState(), hours, context(ms(day, 10)))
        val valid = RecordOvertimeState(false, ms(day, 18), ms(day, 19), null, 1.0, null, null)
        for ((state, canEdit, captures) in listOf(
            Triple(valid, false, true),
            Triple(valid, true, false),
            Triple(valid.copy(endAtMs = valid.startAtMs), true, true),
            Triple(valid.copy(payMultiplier = 0.3), true, true),
            Triple(valid.copy(countedMs = 25 * 3_600_000.0), true, true),
        )) {
            val (next, ok) = RecordEdits.declareOvertime(seeded, day, state, context(ms(day, 20), canEdit), captures)
            assertFalse(ok)
            assertSame(seeded, next)
        }
    }

    @Test fun thePayloadOmitsTheUsualRateAndKeepsTheStart() {
        val state = RecordOvertimeState(false, 1_000.0, 2_000.0, null, 1.0, null, 900.0)
        assertEquals("{\"overtimeEndAtMs\":2000,\"plannedEndAtMs\":900,\"overtimeStartAtMs\":1000}", state.payload)
        val unpaid = state.copy(payMultiplier = 0.0, countedMs = 500.0)
        assertEquals("{\"overtimeEndAtMs\":2000,\"plannedEndAtMs\":900,\"payMultiplier\":0,\"overtimeStartAtMs\":1000,\"countedMs\":500}", unpaid.payload)
    }
}
