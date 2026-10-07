package com.rainif.doneat.plus

import org.junit.Assert.*
import org.junit.Test

class PlusIntroPolicyTest {
    @Test fun freshInstallRemainsUnseenUntilItFinishesSetupAndClosesIntro() {
        assertFalse(PlusIntroPolicy.initialSeen(existingSetup = false, storedSeen = null, damaged = false))
        val ready = PlusIntroState(loaded = true)
        assertFalse(PlusIntroPolicy.shouldPresent(ready, setupComplete = false, authorized = false))
        assertTrue(PlusIntroPolicy.shouldPresent(ready, setupComplete = true, authorized = false))
        assertFalse(PlusIntroPolicy.shouldPresent(PlusIntroPolicy.afterFinish(ready, true), true, false))
    }

    @Test fun existingInstallationAndInitiallyRestoredSettingsDoNotReceiveAnExtraIntro() {
        assertTrue(PlusIntroPolicy.initialSeen(existingSetup = true, storedSeen = null, damaged = false))
    }

    @Test fun interruptedFreshIntroKeepsUnseenEvenThoughSetupIsNowComplete() {
        assertFalse(PlusIntroPolicy.initialSeen(existingSetup = true, storedSeen = false, damaged = false))
        assertTrue(PlusIntroPolicy.initialSeen(existingSetup = false, storedSeen = true, damaged = false))
    }

    @Test fun membershipOrUnloadedMarkerNeverShowsIntro() {
        assertFalse(PlusIntroPolicy.shouldPresent(PlusIntroState(), true, false))
        assertFalse(PlusIntroPolicy.shouldPresent(PlusIntroState(loaded = true), true, true))
    }

    @Test fun damagedMarkerAndFailedSeenSaveCannotTrapUserOnPaywall() {
        assertTrue(PlusIntroPolicy.initialSeen(false, null, damaged = true))
        val next = PlusIntroPolicy.afterFinish(PlusIntroState(loaded = true), persisted = false)
        assertTrue(next.seen); assertTrue(next.writeFailed)
        assertFalse(PlusIntroPolicy.shouldPresent(next, true, false))
    }
}
