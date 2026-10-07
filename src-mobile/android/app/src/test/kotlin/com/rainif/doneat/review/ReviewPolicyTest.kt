package com.rainif.doneat.review

import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReviewPolicyTest {
    private fun completedDays(count: Int, initial: ReviewPolicy = ReviewPolicy()): ReviewPolicy =
        (1..count).fold(initial) { state, day -> state.completed("2026-10-${day.toString().padStart(2, '0')}") }

    @Test fun aSingleTrialDayAndTwoDaysAreNotYetDue() {
        assertFalse(completedDays(1).isDue("3.2.1", 1_000))
        assertFalse(completedDays(2).isDue("3.2.1", 1_000))
        assertTrue(completedDays(3).isDue("3.2.1", 1_000))
    }

    @Test fun returningToCompletedSurfaceCountsTheSameDayOnce() {
        val first = ReviewPolicy().completed("2026-10-01")
        val repeated = (1..5).fold(first) { state, _ -> state.completed("2026-10-01") }
        assertEquals(1, repeated.completedDays)
        assertEquals(first, repeated)
    }

    @Test fun continuingWorkRevokesThatDayAndLaterCompletionCountsAgain() {
        val revoked = completedDays(3).revoked("2026-10-03")
        assertEquals(2, revoked.completedDays)
        assertFalse(revoked.isDue("3.2.1", 1_000))
        assertEquals(revoked, revoked.revoked("2026-10-03"))
        assertEquals(3, revoked.completed("2026-10-03").completedDays)
        assertEquals(revoked, revoked.revoked("2026-10-02"))
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
        val disabled = completedDays(3).disable()
        assertFalse(disabled.isDue("3.2.1", 1_000))
        assertFalse(disabled.canOffer(1_000, "3.2.2", 1_000))
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

    @Test fun onlyTheRealClockOffWindowCanOfferFollowingACelebration() {
        val state = completedDays(3)
        val end = 1_000_000L
        val window = ReviewPolicy.COMPLETION_WINDOW_MS
        assertTrue(state.canOffer(end, "3.2.1", end - window))
        assertTrue(state.canOffer(end, "3.2.1", end + window))
        assertFalse(state.canOffer(end, "3.2.1", end - window - 1))
        assertFalse(state.canOffer(end, "3.2.1", end + window + 1))
        assertFalse(completedDays(2).canOffer(end, "3.2.1", end))
    }

    @Test fun celebrationMustFinishBeforeRequesting() {
        val offer = ReviewOffer(1, 1_000)
        assertFalse(offer.hasSettled(999))
        assertFalse(offer.hasSettled(6_999))
        assertTrue(offer.hasSettled(7_000))
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
}
