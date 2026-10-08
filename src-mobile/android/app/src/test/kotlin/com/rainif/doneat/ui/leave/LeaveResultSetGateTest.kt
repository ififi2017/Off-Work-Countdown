package com.rainif.doneat.ui.leave

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LeaveResultSetGateTest {
    @Test fun `one set consumes once before opening and preserves previously used quota`() = runTest {
        var used = 2
        val result = LeaveResultSetGate().generate({ false }, { 3 - used }, { listOf("A", "B", "C") }, { used++; true })
        assertEquals(3, used)
        assertEquals(listOf("A", "B", "C"), (result as LeaveResultSetOutcome.Results<String>).proposals)
        // All choices are the same already-reserved set, including viewing its final option.
        assertEquals("C", result.proposals.last())
        assertEquals(3, used)
    }

    @Test fun `empty failed or plus searches do not consume`() = runTest {
        var consumes = 0
        val gate = LeaveResultSetGate()
        val consume: suspend () -> Boolean = { consumes++; true }
        assertEquals(LeaveResultSetOutcome.Results(emptyList<String>()), gate.generate({ false }, { 3 }, { emptyList<String>() }, consume))
        assertEquals(LeaveResultSetOutcome.Failed, gate.generate<String>({ false }, { 3 }, { error("search failed") }, consume))
        assertEquals(LeaveResultSetOutcome.Results(listOf("A")), gate.generate({ true }, { 0 }, { listOf("A") }, consume))
        assertEquals(0, consumes)
    }

    @Test fun `exhaustion goes to paywall before searching and reservation race cannot open`() = runTest {
        var searched = false
        val gate = LeaveResultSetGate()
        assertEquals(LeaveResultSetOutcome.Paywall, gate.generate({ false }, { 0 }, { searched = true; listOf("A") }, { error("must not consume") }))
        assertFalse(searched)
        assertEquals(LeaveResultSetOutcome.Paywall, gate.generate({ false }, { 1 }, { listOf("A") }, { false }))
    }

    @Test fun `failed persistence does not return any browsable result and retry succeeds`() = runTest {
        val gate = LeaveResultSetGate()
        assertEquals(LeaveResultSetOutcome.Failed, gate.generate({ false }, { 1 }, { listOf("A") }, { error("atomic write failed") }))
        assertEquals(LeaveResultSetOutcome.Results(listOf("A")), gate.generate({ false }, { 1 }, { listOf("A") }, { true }))
    }

    @Test fun `double tap shares one in flight generation and cancellation never reserves`() = runTest {
        val gate = LeaveResultSetGate()
        val entered = CompletableDeferred<Unit>()
        val found = CompletableDeferred<List<String>>()
        var consumes = 0
        val first = async { gate.generate({ false }, { 3 }, { entered.complete(Unit); found.await() }, { consumes++; true }) }
        entered.await()
        assertEquals(LeaveResultSetOutcome.Busy, gate.generate<String>({ false }, { 3 }, { error("second search") }, { error("second reserve") }))
        first.cancel()
        first.join()
        assertTrue(first.isCancelled)
        assertEquals(0, consumes)
        assertEquals(LeaveResultSetOutcome.Results(listOf("retry")), gate.generate({ false }, { 3 }, { listOf("retry") }, { consumes++; true }))
        assertEquals(1, consumes)
    }

    @Test fun `purchase completed during search exempts the set from a trial`() = runTest {
        var plus = false
        val result = LeaveResultSetGate().generate({ plus }, { 1 }, { plus = true; listOf("A") }, { error("Plus cannot be charged") })
        assertEquals(LeaveResultSetOutcome.Results(listOf("A")), result)
    }
    @Test fun `closed adjustment route cancels before reserving even while its outgoing UI remains composed`() = runTest {
        var routePresent = true
        var used = 1
        var opened = listOf("original")
        val gate = LeaveResultSetGate()
        val result = runCatching {
            gate.generate({ false }, { 3 - used }, { routePresent = false; listOf("replacement") },
                { used++; true }, { routePresent })
        }
        result.getOrNull()?.let { if (it is LeaveResultSetOutcome.Results) opened = it.proposals }
        assertTrue(result.exceptionOrNull() is CancellationException)
        assertEquals(listOf("original"), opened)
        assertEquals(1, used)
    }

    @Test fun `empty adjustment leaves its opened set untouched and a later successful adjustment consumes once`() = runTest {
        var opened = listOf("original")
        var used = 1
        val gate = LeaveResultSetGate()
        suspend fun accept(found: List<String>) {
            val result = gate.generate({ false }, { 3 - used }, { found }, { used++; true })
            if (result is LeaveResultSetOutcome.Results && shouldPublishLeaveResults(opened.isNotEmpty(), result.proposals.isNotEmpty(), true)) opened = result.proposals
        }
        accept(emptyList())
        assertEquals(listOf("original"), opened)
        assertEquals(1, used)
        accept(listOf("replacement", "another choice"))
        assertEquals(listOf("replacement", "another choice"), opened)
        assertEquals(2, used)
    }

}
