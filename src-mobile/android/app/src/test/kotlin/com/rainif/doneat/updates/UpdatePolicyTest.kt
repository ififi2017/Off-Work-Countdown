package com.rainif.doneat.updates

import org.junit.Assert.*
import org.junit.Test

class UpdatePolicyTest {
    private val now = 2_000_000_000_000L
    @Test fun requestsAreLimitedEvenAfterFailedAttempts() {
        assertTrue(UpdatePolicy.checkDue(now, 0))
        assertFalse(UpdatePolicy.checkDue(now, now))
        assertFalse(UpdatePolicy.checkDue(now, now - UpdatePolicy.CHECK_INTERVAL + 1))
        assertTrue(UpdatePolicy.checkDue(now, now - UpdatePolicy.CHECK_INTERVAL))
        assertTrue(UpdatePolicy.checkDue(now, now + 1))
    }
    @Test fun sameVersionIsQuietForAWeekButNewVersionsCanNotify() {
        assertFalse(UpdatePolicy.reminderDue(now, 7, 7, now - UpdatePolicy.REMIND_INTERVAL + 1))
        assertTrue(UpdatePolicy.reminderDue(now, 7, 7, now - UpdatePolicy.REMIND_INTERVAL))
        assertTrue(UpdatePolicy.reminderDue(now, 8, 7, now))
        assertTrue(UpdatePolicy.reminderDue(now, 7, 7, now + 1))
    }
    @Test fun notesAreOptionalPlainTextAndBounded() {
        val base = """{"schemaVersion":1,"applicationId":"com.rainif.doneat.cn","channel":"cn","versionCode":7,"versionName":"3.2.1","minSdk":26"""
        val result = AppUpdates.evaluate(base + """, "releaseNotes":{"en":"Fixes","zh-CN":"改进"}}""", 6, 36) as UpdateResult.Available
        assertEquals("改进", result.release.releaseNotes["zh-CN"])
        assertTrue(runCatching { AppUpdates.evaluate(base + """, "releaseNotes":{"en":"${"x".repeat(3001)}"}}""", 6, 36) }.isFailure)
        assertTrue(AppUpdates.evaluate(base + "}", 6, 36) is UpdateResult.Available)
    }
}
