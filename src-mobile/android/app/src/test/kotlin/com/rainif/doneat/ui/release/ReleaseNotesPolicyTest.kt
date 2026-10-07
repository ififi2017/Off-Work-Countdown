package com.rainif.doneat.ui.release

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReleaseNotesPolicyTest {
    @Test fun `unloaded archive cannot be mistaken for fresh installation`() {
        assertFalse(ReleaseNotesPolicy.shouldPresent(false, true, null))
        assertFalse(ReleaseNotesPolicy.shouldPresent(false, false, null))
    }

    @Test fun `existing and restored setup shows introduction until continue is saved`() {
        for (seen in listOf(null, "3.1.8", "3.1.9", "3.2.0")) {
            assertTrue(ReleaseNotesPolicy.shouldPresent(true, true, seen))
            assertFalse(ReleaseNotesPolicy.marksSeenOnInitialLoad(true))
            val saved = ReleaseNotesPolicy.afterMarkSeen(ReleaseNotesState(true, seen), persisted = true)
            assertFalse(ReleaseNotesPolicy.shouldPresent(saved.loaded, true, saved.seenRelease))
        }
    }

    @Test fun `fresh install does not repeat upgrade introduction after setup`() {
        assertFalse(ReleaseNotesPolicy.shouldPresent(true, false, null))
        assertTrue(ReleaseNotesPolicy.marksSeenOnInitialLoad(false))
        val fresh = ReleaseNotesPolicy.afterMarkSeen(ReleaseNotesState(loaded = true), persisted = true)
        assertFalse(ReleaseNotesPolicy.shouldPresent(true, true, fresh.seenRelease))
    }

    @Test fun `continue write failure retains the old release and visible gate`() {
        val previous = ReleaseNotesState(loaded = true, seenRelease = "3.2.0")
        val failed = ReleaseNotesPolicy.afterMarkSeen(previous, persisted = false)
        assertEquals("3.2.0", failed.seenRelease)
        assertTrue(failed.writeFailed)
        assertTrue(ReleaseNotesPolicy.shouldPresent(failed.loaded, true, failed.seenRelease))
        val retried = ReleaseNotesPolicy.afterMarkSeen(failed, persisted = true)
        assertFalse(retried.writeFailed)
        assertFalse(ReleaseNotesPolicy.shouldPresent(true, true, retried.seenRelease))
    }

    @Test fun `current release stays seen regardless of build number`() {
        assertFalse(ReleaseNotesPolicy.shouldPresent(true, true, ReleaseNotesPolicy.CURRENT))
        assertFalse(ReleaseNotesPolicy.shouldPresent(true, false, ReleaseNotesPolicy.CURRENT))
    }

    @Test fun `only verified free non subscribers are invited without claiming a gift`() {
        assertTrue(ReleaseNotesPolicy.mayInviteUpdateOffer(false, true, true, false))
        assertFalse(ReleaseNotesPolicy.mayInviteUpdateOffer(true, true, true, false))
        assertFalse(ReleaseNotesPolicy.mayInviteUpdateOffer(false, false, true, false))
        assertFalse(ReleaseNotesPolicy.mayInviteUpdateOffer(false, true, false, false))
        assertFalse(ReleaseNotesPolicy.mayInviteUpdateOffer(false, true, true, true))
        assertFalse(ReleaseNotesPolicy.mayInviteUpdateOffer(false, true, true, false, release = "3.2.2"))
    }
}
