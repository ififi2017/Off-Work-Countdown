package com.rainif.doneat.alarms

import org.junit.Assert.*
import org.junit.Test

class VerifiedAlarmLedgerCommitTest {
    @Test fun completeIdentityMustBeReadBackExactlyIncludingAcceptanceAndToken() {
        var durable = byteArrayOf()
        val commits = VerifiedAlarmLedgerCommit({ durable = it.copyOf() }, { durable })
        val pending = "token=first;accepted=false".toByteArray(Charsets.UTF_8)
        val accepted = "token=first;accepted=true".toByteArray(Charsets.UTF_8)
        assertTrue(commits.save(pending))
        assertTrue(commits.save(accepted))
        assertArrayEquals(accepted, durable)
    }

    @Test fun silentRenameFailureCannotConfirmNewRegistrationOrAcceptedPhase() {
        val pending = "token=first;accepted=false".toByteArray(Charsets.UTF_8)
        val accepted = "token=first;accepted=true".toByteArray(Charsets.UTF_8)
        val stale = VerifiedAlarmLedgerCommit({}, { pending })
        assertFalse(stale.save(accepted))
        assertFalse(stale.save("token=second;accepted=false".toByteArray(Charsets.UTF_8)))
    }

    @Test fun missingTruncatedOrThrownReadAndThrownWriteFailClosed() {
        val identity = "完整 registration identity".toByteArray(Charsets.UTF_8)
        assertFalse(VerifiedAlarmLedgerCommit({}, { byteArrayOf() }).save(identity))
        assertFalse(VerifiedAlarmLedgerCommit({}, { identity.copyOfRange(0, 3) }).save(identity))
        assertFalse(VerifiedAlarmLedgerCommit({}, { error("read failed") }).save(identity))
        assertFalse(VerifiedAlarmLedgerCommit({ error("sync failed") }, { identity }).save(identity))
    }
    @Test fun silentAcceptedSaveFailureRollsBackActualSystemRegistration() {
        var durable = byteArrayOf()
        var writes = 0
        var systemAccepted = false
        val commit = VerifiedAlarmLedgerCommit({ if (++writes == 1) durable = it.copyOf() }, { durable })
        val result = commitShiftAlarmRegistration(
            persistPending = { commit.save("token=owned;accepted=false".toByteArray()) },
            register = { systemAccepted = true },
            persistAccepted = { commit.save("token=owned;accepted=true".toByteArray()) },
            rollback = { systemAccepted = false },
        )
        assertEquals(AlarmScheduleOutcome.FAILED, result)
        assertFalse(systemAccepted)
        assertEquals(2, writes)
    }

    @Test fun failedPendingSaveNeverCallsSystemAndSystemFailureAlwaysRollsBack() {
        var launches = 0
        var rollbacks = 0
        assertEquals(AlarmScheduleOutcome.FAILED, commitShiftAlarmRegistration({ false }, { launches++ },
            { true }, { rollbacks++ }))
        assertEquals(0, launches)
        assertEquals(1, rollbacks)
        for (error in listOf(SecurityException("revoked"), IllegalStateException("capacity"), RuntimeException("platform"))) {
            val result = commitShiftAlarmRegistration({ true }, { throw error }, { fail("must not confirm"); true }, { rollbacks++ })
            assertEquals(if (error is IllegalStateException) AlarmScheduleOutcome.LIMIT else AlarmScheduleOutcome.FAILED, result)
        }
        assertEquals(4, rollbacks)
    }

}
