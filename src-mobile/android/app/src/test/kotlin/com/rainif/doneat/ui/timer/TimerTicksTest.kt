package com.rainif.doneat.ui.timer

import com.rainif.doneat.core.domain.session.*
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.settings.PreferencesRules
import java.time.Instant
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class TimerTicksTest {
    @Test fun resumingAfterNinetySecondsReadsTheClockWithoutReplayingTicks() = runTest {
        var clock = 59_750L
        val ticks = timerTicks { clock }
        val values = mutableListOf<Double>()
        val first = launch { ticks.toList(values) }
        runCurrent()
        assertEquals(listOf(59_750.0), values)
        first.cancelAndJoin() // collectAsStateWithLifecycle stops collection off-screen.
        clock += 90_000
        advanceTimeBy(90_000)
        val resumed = launch { ticks.take(2).toList(values) }
        runCurrent()
        assertEquals(listOf(59_750.0, 149_750.0), values)
        clock = 150_000
        advanceTimeBy(250)
        runCurrent()
        resumed.join()
        assertEquals(listOf(59_750.0, 149_750.0, 150_000.0), values)
    }

    @Test fun aStalledTickerCrossingClockOffImmediatelyShowsCompleted() = runTest {
        var clock = Instant.parse("2026-09-16T16:59:00Z").toEpochMilli()
        val session = ShiftSession(SessionState(countdownStarted = true), SessionEnvironment(
            PreferencesRules.defaults("UTC", 0.0).copy(scheduleMode = "classic", workdays = listOf(1, 2, 3, 4, 5),
                startMinutes = 9 * 60, endMinutes = 17 * 60, lunchEnabled = false),
            true, null, emptyList(), HolidayCalendar.EMPTY, "UTC",
        ))
        val phases = mutableListOf<TimerPhase>()
        val remaining = mutableListOf<Double>()
        val job = launch { timerTicks { clock }.collect { now ->
            val snapshot = session.snapshot(now)!!
            phases += session.visualPhase(snapshot, now)
            remaining += snapshot.remainingMs
        } }
        runCurrent()
        clock += 90_000
        advanceTimeBy(1_000)
        runCurrent()
        assertEquals(listOf(TimerPhase.RUNNING, TimerPhase.COMPLETED), phases)
        assertEquals(listOf(60_000.0, 0.0), remaining)
        job.cancelAndJoin()
    }

    @Test fun delayedCollectionAndClockCorrectionsAlwaysUseAbsoluteTime() = runTest {
        var clock = 10_250L
        val values = mutableListOf<Double>()
        val job = launch { timerTicks { clock }.toList(values) }
        runCurrent()
        clock = 100_250L // A stalled foreground resumes 90 seconds later.
        advanceTimeBy(750)
        runCurrent()
        assertEquals(listOf(10_250.0, 100_250.0), values)
        clock = 5_000L // A wall-clock correction is not another elapsed tick.
        advanceTimeBy(750)
        runCurrent()
        assertEquals(5_000.0, values.last(), 0.0)
        job.cancelAndJoin()
    }

    @Test fun countdownRoundingMatchesAppTextAtSecondMinuteAndHourBoundaries() {
        // Pinned iOS AppText.formatDuration: truncate milliseconds, then clamp at zero.
        val cases = mapOf(
            -1_001.0 to "00:00:00", -1.0 to "00:00:00", 0.0 to "00:00:00",
            999.999 to "00:00:00", 1_000.0 to "00:00:01", 1_000.001 to "00:00:01",
            59_999.999 to "00:00:59", 60_000.0 to "00:01:00", 60_000.001 to "00:01:00",
            3_599_999.999 to "00:59:59", 3_600_000.0 to "01:00:00",
            86_400_000.0 to "24:00:00", 360_000_000.0 to "100:00:00",
        )
        cases.forEach { (ms, expected) -> assertEquals("$ms", expected, TimerText.countdownDuration(ms)) }
    }
}
