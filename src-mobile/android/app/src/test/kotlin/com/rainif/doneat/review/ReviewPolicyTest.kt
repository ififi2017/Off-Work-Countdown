package com.rainif.doneat.review

import com.rainif.doneat.ui.Route
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReviewPolicyTest {
    private fun completedDays(count: Int, initial: ReviewPolicy = ReviewPolicy()): ReviewPolicy =
        (1..count).fold(initial) { state, day -> state.completed("2026-10-${day.toString().padStart(2, '0')}") }

    private fun foreground(
        nowMs: Long = 10_000,
        todayKey: String = "2026-10-21",
        offWorkAtMs: Long? = 5_000,
        finishedShiftDayKey: String? = null,
        blocker: ReviewBlocker = ReviewBlocker.NONE,
    ) = ReviewForeground(nowMs, todayKey, offWorkAtMs, finishedShiftDayKey, blocker)

    @Test fun oneFinishedDayIsNotYetDueAndTwoAre() {
        assertFalse(completedDays(1).isDue("3.2.1", 1_000))
        assertTrue(completedDays(2).isDue("3.2.1", 1_000))
        assertEquals(2, ReviewPolicy.MINIMUM_COMPLETED_DAYS)
    }

    @Test fun returningToCompletedSurfaceCountsTheSameDayOnce() {
        val first = ReviewPolicy().completed("2026-10-01")
        val repeated = (1..5).fold(first) { state, _ -> state.completed("2026-10-01") }
        assertEquals(1, repeated.completedDays)
        assertEquals(first, repeated)
    }

    @Test fun continuingWorkRevokesThatDayAndLaterCompletionCountsAgain() {
        val revoked = completedDays(2).revoked("2026-10-02")
        assertEquals(1, revoked.completedDays)
        assertFalse(revoked.isDue("3.2.1", 1_000))
        assertEquals(revoked, revoked.revoked("2026-10-02"))
        assertEquals(2, revoked.completed("2026-10-02").completedDays)
        assertEquals(revoked, revoked.revoked("2026-10-01"))
    }

    @Test fun suppressedOrFailedPlayRequestStartsCountingAgain() {
        val requested = completedDays(3).requested("3.2.1", 2_000)
        assertEquals(0, requested.completedDays)
        assertEquals("3.2.1", requested.lastRequestVersion)
        assertEquals(2_000L, requested.lastRequestAtMs)
        // Reopening/replaying the just-requested day's completion cannot start the new count.
        assertEquals(0, requested.completed("2026-10-03").completedDays)
        assertFalse(requested.isDue("3.2.2", 2_000 + ReviewPolicy.REQUEST_GAP_MS))
    }

    @Test fun requestsNeedAnotherVersionAndAtLeast120Days() {
        var state = completedDays(3).requested("3.2.1", 2_000)
        for (day in 4..6) state = state.completed("2026-10-0$day")
        val boundary = 2_000 + ReviewPolicy.REQUEST_GAP_MS
        assertEquals(120L * 24 * 60 * 60 * 1_000, ReviewPolicy.REQUEST_GAP_MS)
        assertFalse(state.isDue("3.2.2", boundary - 1))
        assertTrue(state.isDue("3.2.2", boundary))
        assertFalse(state.isDue("3.2.1", boundary + 1))
        assertFalse(state.isDue("3.2.2", 1_999)) // A clock rollback must not bypass the interval.
    }

    @Test fun manualReviewPermanentlyDisablesAutomaticRequests() {
        val disabled = completedDays(2).disable()
        assertFalse(disabled.isDue("3.2.1", 1_000))
        assertFalse(disabled.onForeground(foreground(), "3.2.2").request)
        assertEquals(disabled, disabled.completed("2026-10-04"))
    }

    @Test fun oldDeviceStateRetainsThrottleButStartsWithNoHabitOrLaunchOffer() {
        // Only these legacy fields are restored; tracked_end, ready_end and handled_end are discarded.
        val legacy = ReviewPolicy(lastRequestAtMs = 2_000, disabled = false)
        assertEquals(0, legacy.completedDays)
        assertFalse(legacy.isDue("3.2.1", 2_000 + ReviewPolicy.REQUEST_GAP_MS))
        val migrated = completedDays(3, legacy)
        assertFalse(migrated.isDue("3.2.1", 2_000 + ReviewPolicy.REQUEST_GAP_MS - 1))
        assertTrue(migrated.isDue("3.2.1", 2_000 + ReviewPolicy.REQUEST_GAP_MS))
        assertFalse(completedDays(3, legacy.disable()).isDue("3.2.1", Long.MAX_VALUE))
    }

    @Test fun theFirstForegroundAfterOffWorkRequestsAndASecondOpenTheSameDayDoesNot() {
        val due = completedDays(2)
        val before = foreground(nowMs = 4_999, offWorkAtMs = 5_000, finishedShiftDayKey = null)
        val tooEarly = due.onForeground(before, "3.2.1")
        assertFalse(tooEarly.request)
        assertEquals(due, tooEarly.policy)

        val opened = tooEarly.policy.onForeground(foreground(), "3.2.1")
        assertTrue(opened.request)
        assertEquals("2026-10-21", opened.policy.lastAttemptDayKey)
        assertEquals("3.2.1", opened.policy.lastRequestVersion)
        assertEquals(0, opened.policy.completedDays)

        val again = opened.policy.onForeground(foreground(nowMs = 20_000), "3.2.1")
        assertFalse(again.request)
        assertEquals(opened.policy, again.policy)
    }

    @Test fun anOpenBeforeOffWorkDoesNotUseUpTheDaysFirstForegroundAfterIt() {
        val due = completedDays(2)
        val morning = due.onForeground(
            foreground(nowMs = 1_000, offWorkAtMs = 8_000, finishedShiftDayKey = null),
            "3.2.1",
        )
        assertFalse(morning.request)
        assertNull(morning.policy.lastAttemptDayKey)
        assertTrue(morning.policy.onForeground(foreground(nowMs = 8_000, offWorkAtMs = 8_000), "3.2.1").request)
    }

    @Test fun aBlockingLayerDefersWithoutConsumingTheDaysAttempt() {
        val due = completedDays(2)
        for (blocker in listOf(ReviewBlocker.PAYWALL, ReviewBlocker.LIFETIME_GIFT, ReviewBlocker.WHATS_NEW)) {
            val blocked = due.onForeground(foreground(blocker = blocker), "3.2.1")
            assertFalse(blocker.name, blocked.request)
            assertNull(blocked.policy.lastAttemptDayKey)
            assertEquals(2, blocked.policy.completedDays)
            val nextOpen = blocked.policy.onForeground(foreground(nowMs = 12_000), "3.2.1")
            assertTrue(blocker.name, nextOpen.request)
        }
    }

    @Test fun theFinishingOpenCountsThatDayBeforeCheckingTheThreshold() {
        val oneDay = completedDays(1)
        val waiting = oneDay.onForeground(
            foreground(finishedShiftDayKey = "2026-10-02", todayKey = "2026-10-02"),
            "3.2.1",
        )
        assertTrue(waiting.request)
        assertEquals(0, waiting.policy.completedDays)
        val stillOne = ReviewPolicy().onForeground(foreground(finishedShiftDayKey = "2026-10-01"), "3.2.1")
        assertFalse(stillOne.request)
        assertEquals(1, stillOne.policy.completedDays)
        assertNull(stillOne.policy.lastAttemptDayKey)
    }

    @Test fun aRestDayHasNoOffWorkMomentSoItDoesNotAsk() {
        val due = completedDays(2)
        val rest = due.onForeground(foreground(offWorkAtMs = null, finishedShiftDayKey = null), "3.2.1")
        assertFalse(rest.request)
        assertNull(rest.policy.lastAttemptDayKey)
    }

    @Test fun overnightCompletionUsesRecordsCalendarRatherThanStartDayOrDeviceZone() {
        val end = Instant.parse("2026-10-02T00:30:00Z").toEpochMilli()
        assertEquals("2026-10-02", ReviewPolicy.dayKey(end, ZoneId.of("Asia/Shanghai")))
        assertEquals("2026-10-01", ReviewPolicy.dayKey(end, ZoneId.of("America/Los_Angeles")))
        val beforeMidnight = Instant.parse("2026-10-01T15:59:59Z").toEpochMilli()
        val afterMidnight = Instant.parse("2026-10-01T16:00:00Z").toEpochMilli()
        val zone = ZoneId.of("Asia/Shanghai")
        val state = ReviewPolicy().completed(ReviewPolicy.dayKey(beforeMidnight, zone))
            .completed(ReviewPolicy.dayKey(afterMidnight, zone))
        assertEquals(2, state.completedDays)
    }

    @Test fun theSettleWaitIsSixSecondsAndAColdStartIsStillAVisit() {
        assertEquals(6_000L, ReviewPolicy.FOREGROUND_SETTLE_MS)
        val cold = ReviewVisits().onStart()
        assertEquals(1, cold.generation)
        assertFalse(cold.backgrounded)
    }

    @Test fun onlyAReturnFromTheBackgroundStartsAnotherVisit() {
        val cold = ReviewVisits().onStart()
        assertEquals(cold, cold.onStart())
        assertEquals(1, cold.onStop(changingConfigurations = true).onStart().generation)
        assertEquals(2, cold.onStop(changingConfigurations = false).onStart().generation)
    }

    @Test fun leavingDuringTheSettleCancelsThatWait() {
        val visit = ReviewVisits().onStart()
        val (cancelled, ask) = visit.onSettled(visit.generation, stillInForeground = false)
        assertFalse(ask)
        assertEquals(0, cancelled.decided)
        val (ready, decide) = cancelled.onSettled(visit.generation, stillInForeground = true)
        assertTrue(decide)
        assertEquals(1, ready.decided)
        val (again, second) = ready.onSettled(1, true)
        assertFalse(second)
        assertEquals(ready, again)
    }

    @Test fun anOvernightShiftUsesTheRecordsDayAndWaitsUntilThatOffWorkInstant() {
        val zone = ZoneId.of("Asia/Shanghai")
        val offWork = Instant.parse("2026-10-21T22:00:00Z").toEpochMilli()
        val evening = ReviewPolicy.foreground(Instant.parse("2026-10-21T15:00:00Z").toEpochMilli(), offWork, zone)
        assertEquals("2026-10-21", evening.todayKey)
        assertNull(evening.finishedShiftDayKey)
        val afterMidnight = ReviewPolicy.foreground(Instant.parse("2026-10-21T17:00:00Z").toEpochMilli(), offWork, zone)
        assertEquals("2026-10-22", afterMidnight.todayKey)
        assertNull(afterMidnight.finishedShiftDayKey)

        val due = completedDays(2)
        val before = due.onForeground(evening, "3.2.1")
        assertFalse(before.request)
        assertNull(before.policy.lastAttemptDayKey)
        val stillBefore = before.policy.onForeground(afterMidnight, "3.2.1")
        assertFalse(stillBefore.request)
        assertNull(stillBefore.policy.lastAttemptDayKey)

        val clockOff = ReviewPolicy.foreground(offWork, offWork, zone)
        assertEquals("2026-10-22", clockOff.todayKey)
        assertEquals("2026-10-22", clockOff.finishedShiftDayKey)
        val asked = stillBefore.policy.onForeground(clockOff, "3.2.1")
        assertTrue(asked.request)
        assertEquals("2026-10-22", asked.policy.lastAttemptDayKey)
        val later = asked.policy.onForeground(ReviewPolicy.foreground(offWork + 60_000, offWork, zone), "3.2.1")
        assertFalse(later.request)
    }

    @Test fun restoredSurfacesDeferWithoutConsumingTheDaysAttempt() {
        val clear = reviewSurfaceBlocker(true, false, Route.TimerHome, timerDialog = false, landscapeClock = false)
        assertEquals(ReviewBlocker.NONE, clear)
        val surfaces = listOf(
            reviewSurfaceBlocker(true, false, Route.TimerHome, timerDialog = true, landscapeClock = false) to ReviewBlocker.DIALOG,
            reviewSurfaceBlocker(true, false, Route.TimerHome, timerDialog = false, landscapeClock = true) to ReviewBlocker.DIALOG,
            reviewSurfaceBlocker(false, false, Route.Schedule, false, false) to ReviewBlocker.SCHEDULE,
            reviewSurfaceBlocker(false, false, Route.ShiftTypeEdit("early", true), false, false) to ReviewBlocker.SCHEDULE,
            reviewSurfaceBlocker(false, false, Route.RecordsDayEdit("2026-10-21"), false, false) to ReviewBlocker.EDITOR,
            reviewSurfaceBlocker(false, false, Route.Salary, false, false) to ReviewBlocker.EDITOR,
            reviewSurfaceBlocker(false, true, Route.FocusHome, false, false) to ReviewBlocker.FOCUS,
            reviewSurfaceBlocker(false, false, Route.TimerShare, false, false) to ReviewBlocker.DIALOG,
            reviewSurfaceBlocker(false, false, Route.SettingsHome, false, false) to ReviewBlocker.DIALOG,
        )
        val due = completedDays(2)
        for ((blocker, expected) in surfaces) {
            assertEquals(expected.name, expected, blocker)
            val blocked = due.onForeground(foreground(blocker = blocker), "3.2.1")
            assertFalse(blocker.name, blocked.request)
            assertNull(blocked.policy.lastAttemptDayKey)
            assertEquals(2, blocked.policy.completedDays)
        }
    }
}
