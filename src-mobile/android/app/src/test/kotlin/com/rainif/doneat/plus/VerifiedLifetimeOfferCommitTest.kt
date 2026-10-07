package com.rainif.doneat.plus

import org.junit.Assert.*
import org.junit.Test

class VerifiedLifetimeOfferCommitTest {
    private val deadline = "claimed:123;latest:456".toByteArray()

    @Test fun committedDeadlineMustReadBackExactly() {
        var disk = byteArrayOf()
        assertTrue(confirmedLifetimeOfferWrite(deadline, { disk = it.copyOf() }, { disk }))
    }

    @Test fun silentlyDiscardedOrTruncatedWriteDoesNotCommit() {
        assertFalse(confirmedLifetimeOfferWrite(deadline, {}, { "unclaimed".toByteArray() }))
        assertFalse(confirmedLifetimeOfferWrite(deadline, {}, { deadline.dropLast(1).toByteArray() }))
    }

    @Test fun writeOrReadFailureDoesNotCommit() {
        assertFalse(confirmedLifetimeOfferWrite(deadline, { error("sync failed") }, { deadline }))
        assertFalse(confirmedLifetimeOfferWrite(deadline, {}, { error("read failed") }))
    }
}
