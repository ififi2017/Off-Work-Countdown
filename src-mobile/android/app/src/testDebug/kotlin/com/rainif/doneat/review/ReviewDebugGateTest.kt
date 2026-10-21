package com.rainif.doneat.review

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Compiled only for the debug unit-test variant. Release does not see this source set. */
class ReviewDebugGateTest {
    private fun event(
        nowMs: Long = 10_000,
        offWorkAtMs: Long? = 5_000,
        blocker: ReviewBlocker = ReviewBlocker.NONE,
    ) = ReviewForeground(nowMs, "2026-10-21", offWorkAtMs, finishedShiftDayKey = null, blocker = blocker)

    @Test fun ignoreThresholdsStillWaitsForOffWorkAClearForegroundAndOneAttempt() {
        val fresh = ReviewPolicy()
        val before = fresh.debugIntercept(ReviewDebugMode.IGNORE, event(nowMs = 1_000, offWorkAtMs = 5_000))
        assertFalse(before.result.request)
        assertFalse(before.consumeForce)
        assertNull(before.result.policy.lastAttemptDayKey)

        val blocked = fresh.debugIntercept(ReviewDebugMode.IGNORE, event(blocker = ReviewBlocker.WHATS_NEW))
        assertFalse(blocked.result.request)
        assertNull(blocked.result.policy.lastRequestVersion)

        val asked = fresh.debugIntercept(ReviewDebugMode.IGNORE, event())
        assertTrue(asked.result.request)
        assertEquals("2026-10-21", asked.result.policy.lastAttemptDayKey)
        assertNull(asked.result.policy.lastRequestVersion)
        assertEquals(0, asked.result.policy.completedDays)

        val later = asked.result.policy.debugIntercept(ReviewDebugMode.IGNORE, event(nowMs = 11_000))
        assertFalse(later.result.request)
    }

    @Test fun forceAsksOnceWithoutRewritingEligibilityAndWaitsOutALayer() {
        val due = ReviewPolicy(completedDays = 2, lastRequestVersion = "3.2.1", lastRequestAtMs = 1)
        val blocked = due.debugIntercept(ReviewDebugMode.FORCE, event(blocker = ReviewBlocker.PAYWALL))
        assertFalse(blocked.result.request)
        assertFalse(blocked.consumeForce)
        assertEquals(due, blocked.result.policy)

        val gift = due.debugIntercept(ReviewDebugMode.FORCE, event(blocker = ReviewBlocker.LIFETIME_GIFT))
        assertFalse(gift.result.request)
        assertFalse(gift.consumeForce)

        val asked = due.debugIntercept(ReviewDebugMode.FORCE, event())
        assertTrue(asked.result.request)
        assertTrue(asked.consumeForce)
        assertEquals(due, asked.result.policy)
    }

    @Test fun aManualOptOutStillBlocksTheThresholdOverride() {
        val disabled = ReviewPolicy(completedDays = 2).disable()
        val result = disabled.debugIntercept(ReviewDebugMode.IGNORE, event())
        assertFalse(result.result.request)
        assertEquals(disabled, result.result.policy)
    }
}
