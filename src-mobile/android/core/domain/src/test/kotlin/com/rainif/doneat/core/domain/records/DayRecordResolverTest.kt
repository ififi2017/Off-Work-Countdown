package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.records.RecordTestFixtures.holiday
import com.rainif.doneat.core.domain.records.RecordTestFixtures.id
import com.rainif.doneat.core.domain.records.RecordTestFixtures.ms
import com.rainif.doneat.core.domain.records.RecordTestFixtures.override
import com.rainif.doneat.core.domain.records.RecordTestFixtures.period
import com.rainif.doneat.core.domain.records.RecordTestFixtures.segment
import com.rainif.doneat.core.domain.records.RecordTestFixtures.snapshot
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** One-to-one with iOS `DayRecordResolverTests`. */
class DayRecordResolverTest {
    private fun weekday(dayKey: String) = listOf(segment(dayKey, 9, 17))

    private fun resolve(
        dayKey: String,
        snapshots: List<ScheduleSnapshot>? = null,
        exceptions: List<CalendarException> = emptyList(),
        overrides: List<DayOverride> = emptyList(),
    ) = DayRecordResolver.resolve(
        dayKey,
        periods = listOf(period(id(1), "2024-01-01")),
        snapshots = snapshots ?: listOf(snapshot(id(10), id(1), "2024-01-01", "weekday")),
        exceptions = exceptions,
        overrides = overrides,
        expand = { ScheduleExpansion(it.fingerprint != "rest", weekday(dayKey)) },
    )

    @Test fun noPeriodResolvesToNone() {
        val r = DayRecordResolver.resolve("2026-08-24", emptyList(), emptyList(), emptyList(), emptyList()) { ScheduleExpansion.NONE }
        assertEquals(DayResolutionLayer.NONE, r.layer)
        assertFalse(r.isScheduledWorkday)
        assertTrue(r.segments.isEmpty())
    }

    @Test fun endedPeriodDoesNotCoverLaterDays() {
        val p = period(id(1), "2024-01-01", endsBefore = "2026-08-01")
        assertEquals(id(1), DayRecordResolver.period("2026-07-31", listOf(p))?.id)
        assertNull(DayRecordResolver.period("2026-08-01", listOf(p)))
        assertNull(DayRecordResolver.period("2026-08-24", listOf(p)))
    }

    @Test fun overlappingPeriodsPickLaterStart() {
        val older = period(id(1), "2020-01-01")
        val newer = period(id(2), "2025-06-01")
        assertEquals(id(2), DayRecordResolver.period("2026-08-24", listOf(older, newer))?.id)
        assertEquals(id(1), DayRecordResolver.period("2024-01-01", listOf(older, newer))?.id)
    }

    @Test fun overlappingPeriodsBreakTies() {
        val earlier = period(id(2), "2024-01-01", createdOn = "2024-01-01")
        val laterCreated = period(id(1), "2024-01-01", createdOn = "2025-01-01")
        assertEquals(id(1), DayRecordResolver.period("2026-08-24", listOf(earlier, laterCreated))?.id)
        val low = period(id(1), "2024-01-01")
        val high = period(id(2), "2024-01-01")
        assertEquals(id(2), DayRecordResolver.period("2026-08-24", listOf(low, high))?.id)
    }

    @Test fun latestEffectiveSnapshotWins() {
        val p = period(id(1), "2024-01-01")
        val first = snapshot(id(10), id(1), "2024-01-01", "old")
        val second = snapshot(id(11), id(1), "2026-07-01", "new")
        val future = snapshot(id(12), id(1), "2026-09-01", "future")
        assertEquals(id(11), DayRecordResolver.snapshot("2026-08-24", p, listOf(first, second, future))?.id)
        assertEquals(id(10), DayRecordResolver.snapshot("2025-01-01", p, listOf(first, second))?.id)
    }

    @Test fun sameSlotSnapshotPicksEditStamp() {
        val p = period(id(1), "2024-01-01")
        val losing = snapshot(id(10), id(1), "2026-07-01", "a", editCount = 1, tie = id(1))
        val winningCount = snapshot(id(9), id(1), "2026-07-01", "b", editCount = 2, tie = id(1))
        assertEquals(id(9), DayRecordResolver.snapshot("2026-08-24", p, listOf(losing, winningCount))?.id)
        val lowTie = snapshot(id(20), id(1), "2026-07-01", "c", editCount = 3, tie = id(1))
        val highTie = snapshot(id(19), id(1), "2026-07-01", "d", editCount = 3, tie = id(2))
        assertEquals(id(19), DayRecordResolver.snapshot("2026-08-24", p, listOf(lowTie, highTie))?.id)
    }

    @Test fun customOverrideBeatsExceptionAndSchedule() {
        val custom = listOf(segment("2026-08-24", 10, 19))
        val r = resolve(
            "2026-08-24",
            exceptions = listOf(holiday("2026-08-24", CalendarEffect.REST, CalendarExceptionOrigin.USER)),
            overrides = listOf(override("2026-08-24", DayOverrideKind.CUSTOM_SEGMENTS, custom)),
        )
        assertEquals(DayResolutionLayer.OVERRIDE, r.layer)
        assertTrue(r.isScheduledWorkday)
        assertEquals(custom, r.segments)
        assertTrue(r.baseScheduleIsWorkday)
        assertEquals(weekday("2026-08-24"), r.baseScheduleSegments)
    }

    @Test fun leaveOverrideIsNotAHoliday() {
        val r = resolve(
            "2026-08-28",
            exceptions = listOf(holiday("2026-08-28", CalendarEffect.WORK, CalendarExceptionOrigin.USER)),
            overrides = listOf(override("2026-08-28", DayOverrideKind.NOT_WORKING)),
        )
        assertEquals(DayResolutionLayer.OVERRIDE, r.layer)
        assertFalse(r.isScheduledWorkday)
        assertTrue(r.segments.isEmpty())
        assertTrue(r.baseScheduleIsWorkday)
        assertEquals(weekday("2026-08-28"), r.baseScheduleSegments)
    }

    @Test fun clearedOverrideFallsThrough() {
        val cleared = override("2026-08-24", DayOverrideKind.CLEARED)
        val r = resolve("2026-08-24", overrides = listOf(cleared))
        assertEquals(DayResolutionLayer.SCHEDULE, r.layer)
        assertTrue(r.isScheduledWorkday)
        assertNull(DayRecordResolver.dayOverride("2026-08-24", listOf(cleared)))
    }

    @Test fun confirmedOverrideKeepsScheduleHours() {
        val r = resolve("2026-08-24", overrides = listOf(override("2026-08-24", DayOverrideKind.CONFIRMED_AS_SCHEDULED)))
        assertEquals(DayResolutionLayer.OVERRIDE, r.layer)
        assertTrue(r.isScheduledWorkday)
        assertEquals(weekday("2026-08-24"), r.segments)
    }

    @Test fun userHolidayBeatsSchedule() {
        val r = resolve("2026-08-24", exceptions = listOf(holiday("2026-08-24", CalendarEffect.REST, CalendarExceptionOrigin.USER)))
        assertEquals(DayResolutionLayer.CALENDAR_EXCEPTION, r.layer)
        assertFalse(r.isScheduledWorkday)
        assertTrue(r.segments.isEmpty())
        assertTrue(r.baseScheduleIsWorkday)
        assertEquals(weekday("2026-08-24"), r.baseScheduleSegments)
    }

    @Test fun makeupSaturdayUsesScheduleHours() {
        val r = resolve(
            "2026-08-29",
            snapshots = listOf(snapshot(id(11), id(1), "2024-01-01", "rest")),
            exceptions = listOf(holiday("2026-08-29", CalendarEffect.WORK, CalendarExceptionOrigin.USER)),
        )
        assertEquals(DayResolutionLayer.CALENDAR_EXCEPTION, r.layer)
        assertTrue(r.isScheduledWorkday)
        assertEquals(weekday("2026-08-29"), r.segments)
    }

    @Test fun userExceptionBeatsBundledAndClearedFallsThrough() {
        val bundledRest = holiday("2026-08-24", CalendarEffect.REST, CalendarExceptionOrigin.BUNDLED, "2026.1")
        val userWork = holiday("2026-08-24", CalendarEffect.WORK, CalendarExceptionOrigin.USER)
        assertEquals(CalendarExceptionOrigin.USER, DayRecordResolver.exception("2026-08-24", listOf(bundledRest, userWork))?.origin)
        val cleared = bundledRest.copy(isCleared = true)
        assertNull(DayRecordResolver.exception("2026-08-24", listOf(cleared)))
        val r = resolve("2026-08-24", exceptions = listOf(cleared))
        assertEquals(DayResolutionLayer.SCHEDULE, r.layer)
        assertTrue(r.isScheduledWorkday)
    }

    @Test fun newerBundledDatasetWins() {
        val old = holiday("2026-08-24", CalendarEffect.REST, CalendarExceptionOrigin.BUNDLED, "2025.1")
        val new = holiday("2026-08-24", CalendarEffect.WORK, CalendarExceptionOrigin.BUNDLED, "2026.2")
        assertEquals("2026.2", DayRecordResolver.exception("2026-08-24", listOf(old, new))?.datasetVersion)
    }

    @Test fun periodWithoutSnapshotIsNone() {
        val r = DayRecordResolver.resolve("2026-08-24", listOf(period(id(1), "2024-01-01")), emptyList(), emptyList(), emptyList()) { ScheduleExpansion.NONE }
        assertEquals(DayResolutionLayer.NONE, r.layer)
        assertNull(r.snapshotID)
        assertFalse(r.isScheduledWorkday)
    }

    @Test fun overrideDoesNotHideBaseExpansionFailure() {
        val custom = listOf(ShiftSegment(ms("2026-08-24", 10), ms("2026-08-24", 18)))
        val r = DayRecordResolver.resolve(
            "2026-08-24", listOf(period(id(1), "2024-01-01")), listOf(snapshot(id(10), id(1), "2024-01-01", "weekday")),
            emptyList(), listOf(override("2026-08-24", DayOverrideKind.CUSTOM_SEGMENTS, custom)),
        ) { ScheduleExpansion.FAILED }
        assertEquals(custom, r.segments)
        assertTrue(r.expansionFailed)
        assertFalse(r.baseScheduleIsWorkday)
    }

    @Test fun restSnapshotWithoutExceptionIsRest() {
        val r = resolve("2026-08-29", snapshots = listOf(snapshot(id(11), id(1), "2024-01-01", "rest")))
        assertEquals(DayResolutionLayer.SCHEDULE, r.layer)
        assertFalse(r.isScheduledWorkday)
        assertTrue(r.segments.isEmpty())
    }
}
