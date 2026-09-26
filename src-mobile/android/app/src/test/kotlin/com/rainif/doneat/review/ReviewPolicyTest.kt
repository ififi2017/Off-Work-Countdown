package com.rainif.doneat.review

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReviewPolicyTest {
    @Test fun completionArmsNextLaunchAndIsConsumedOnce() {
        val (started, eligibleAtStart) = ReviewPolicy().coldLaunch(500)
        assertFalse(eligibleAtStart)
        val completed = started.completed(1_000)
        val (launched, eligible) = completed.coldLaunch(2_000)
        assertTrue(eligible)
        val requested = launched.requested(2_000)
        assertFalse(requested.coldLaunch(3_000).second)
        assertEquals(1_000L, requested.handledEndAtMs)
    }

    @Test fun trackedRunningShiftCanFinishWhileClosed() {
        val running = ReviewPolicy().trackRunning(2_000, 1_000)
        assertFalse(running.coldLaunch(1_500).second)
        val (finished, eligible) = running.coldLaunch(2_500)
        assertTrue(eligible)
        assertEquals(2_000L, finished.readyEndAtMs)
    }

    @Test fun failedOrSuppressedRequestWaitsForAnotherCompletionAndNinetyDays() {
        val first = ReviewPolicy().completed(1_000).requested(2_000)
        assertFalse(first.completed(1_000).coldLaunch(3_000).second)
        val second = first.completed(4_000)
        assertFalse(second.coldLaunch(2_000 + ReviewPolicy.REQUEST_GAP_MS - 1).second)
        assertTrue(second.coldLaunch(2_000 + ReviewPolicy.REQUEST_GAP_MS).second)
    }

    @Test fun manualReviewPermanentlyDisablesAutomaticRequests() {
        val disabled = ReviewPolicy().trackRunning(2_000, 1_000).disable()
        assertFalse(disabled.coldLaunch(3_000).second)
        assertFalse(disabled.completed(4_000).coldLaunch(5_000).second)
    }

    @Test fun continuingWorkRevokesTheOldBoundary() {
        val continued = ReviewPolicy().completed(2_000).revoked(2_000).trackRunning(3_000, 2_100)
        assertFalse(continued.coldLaunch(2_500).second)
        assertTrue(continued.coldLaunch(3_500).second)
    }
}
