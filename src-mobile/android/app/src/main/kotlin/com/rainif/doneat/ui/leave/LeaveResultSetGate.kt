package com.rainif.doneat.ui.leave

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.util.concurrent.atomic.AtomicBoolean

internal sealed interface LeaveResultSetOutcome<out T> {
    data class Results<T>(val proposals: List<T>) : LeaveResultSetOutcome<T>
    data object Paywall : LeaveResultSetOutcome<Nothing>
    data object Busy : LeaveResultSetOutcome<Nothing>
    data object Failed : LeaveResultSetOutcome<Nothing>
}

/** One successful result set spends one trial; its choices and details reuse that set freely. */
internal class LeaveResultSetGate {
    private val running = AtomicBoolean(false)

    suspend fun <T> generate(
        isPlus: () -> Boolean, trialsLeft: () -> Int,
        find: suspend () -> List<T>, consume: suspend () -> Boolean,
    ): LeaveResultSetOutcome<T> {
        if (!running.compareAndSet(false, true)) return LeaveResultSetOutcome.Busy
        try {
            if (!isPlus() && trialsLeft() <= 0) return LeaveResultSetOutcome.Paywall
            val proposals = find()
            currentCoroutineContext().ensureActive()
            if (proposals.isNotEmpty() && !isPlus() && !consume()) return LeaveResultSetOutcome.Paywall
            return LeaveResultSetOutcome.Results(proposals)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            return LeaveResultSetOutcome.Failed
        } finally {
            running.set(false)
        }
    }
}
