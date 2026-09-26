package com.rainif.doneat.ui.records

import com.rainif.doneat.core.domain.records.*
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class RecordsComputationTest {
    @Test fun leavingLifeCancelsItsRealDayWalkAndCannotReplaceTheNewSelection() = runBlocking {
        val zone = ZoneId.of("UTC")
        val profile = LifeProfiles.blank(0.0) { "life" }.copy(
            bornOn = LifeDates.yearOnly(1980), workStartedPartial = LifeDates.yearOnly(2000),
            retirementOn = LifeDates.yearOnly(2050),
        )
        val query = RecordsQueries(RecordState(lifeProfile = profile), HolidayCalendar.EMPTY, zone, true,
            currentHours = SnapshotHours("09:00", "18:00", listOf(1, 2, 3, 4, 5), "classic", breakStartTime = null, breakDurationMinutes = 0))
        val started = CompletableDeferred<Unit>()
        val release = CountDownLatch(1)
        val checks = AtomicInteger()
        val published = mutableListOf<String>()
        val old = launch {
            computeRecords { check ->
                query.lifeModel(1_800_000_000_000.0, null) {
                    checks.incrementAndGet()
                    started.complete(Unit)
                    kotlin.check(release.await(5, TimeUnit.SECONDS))
                    check()
                }
            }
            published += "Life"
        }
        try {
            withTimeout(5_000) { started.await() }
            old.cancel()
            release.countDown()
            withTimeout(5_000) { old.join() }
            val window = computeRecords { check ->
                query.displayDays(LocalDate.of(2026, 9, 1), LocalDate.of(2026, 9, 30), 1_800_000_000_000.0, check)
            }
            published += "Month"
            assertTrue(old.isCancelled)
            assertEquals(1, checks.get())
            assertEquals(30, window.size)
            assertEquals(listOf("Month"), published)
        } finally { release.countDown(); old.cancelAndJoin() }
    }

    @Test fun historyIndexKeepsFreeRowsPrivateAndUsesCivilKeysInEveryLocale() {
        val rows = listOf("2016-01-02", "2026-09-15", "2026-09-16").map { RecordDayIndexEntry(it) }
        val today = LocalDate.of(2026, 9, 16)
        val free = VisibleRecords(rows, false, today)
        assertEquals(listOf(2026), free.years)
        assertTrue(free.hasLockedHistory)
        assertEquals(2, free.count(2026))
        assertEquals(emptyList<RecordDayIndexEntry>(), free.days(2016, 1))
        val previous = java.util.Locale.getDefault()
        try {
            java.util.Locale.setDefault(java.util.Locale.forLanguageTag("ar"))
            assertEquals(rows.takeLast(2), free.days(2026, 9))
        } finally { java.util.Locale.setDefault(previous) }
    }
}
