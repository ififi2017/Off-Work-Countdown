package com.rainif.doneat.review

import android.content.Context
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import com.google.android.play.core.review.ReviewManagerFactory
import com.rainif.doneat.core.domain.schedule.ShiftSnapshot
import com.rainif.doneat.core.domain.session.ShiftSession

/** Device-local request state. The backup include list excludes SharedPreferences. */
class ReviewCoordinator private constructor(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("play_review", Context.MODE_PRIVATE)
    private var state = ReviewPolicy(
        trackedEndAtMs = prefs.getLong("tracked_end", 0).takeIf { it > 0 },
        readyEndAtMs = prefs.getLong("ready_end", 0).takeIf { it > 0 },
        handledEndAtMs = prefs.getLong("handled_end", 0),
        lastRequestAtMs = prefs.getLong("last_request", 0),
        disabled = prefs.getBoolean("disabled", false),
    )
    private var eligibleThisLaunch: Boolean

    init {
        val (launched, eligible) = state.coldLaunch(System.currentTimeMillis())
        state = launched
        eligibleThisLaunch = eligible
        persist()
    }

    /** Call while a real started shift is running. A scheduled rest day cannot arm review. */
    @Synchronized
    fun trackRunningShift(session: ShiftSession, shift: ShiftSnapshot?, nowMs: Long) {
        if (shift == null || !session.state.countdownStarted || !(shift.isWorkday || session.isForcedWorkday(shift)) ||
            shift.segments.isEmpty() || shift.startAtMs > nowMs || shift.endAtMs <= nowMs
        ) return
        update(state.trackRunning(shift.endAtMs.toLong(), nowMs))
    }

    /** A completed shift arms a future cold launch, never this warm session. */
    @Synchronized
    fun noteCompletion(endAtMs: Long) = update(state.completed(endAtMs))

    /** Undo or extra overtime means the former end was not the final clock-off. */
    @Synchronized
    fun revokeCompletion(endAtMs: Long) = update(state.revoked(endAtMs))

    /** Canceling a manual run must not turn its old projected end into a completed shift. */
    @Synchronized
    fun clearTrackedCompletion() = update(state.copy(trackedEndAtMs = null))

    /** The manual Settings link is explicit and remains usable after automatic requests stop. */
    @Synchronized
    fun disableAutomatic() {
        eligibleThisLaunch = false
        update(state.disable())
    }

    /** Call only from the resumed root activity, with no editor or modal in front. */
    fun requestIfEligible(activity: FragmentActivity, canPresent: () -> Boolean) {
        val now = System.currentTimeMillis()
        synchronized(this) {
            if (!eligibleThisLaunch || state.disabled || !canPresent() ||
                !activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
            ) return
            eligibleThisLaunch = false
            update(state.requested(now))
        }
        // Play may silently suppress the card. A failed request is equally silent and consumed.
        try {
            val manager = ReviewManagerFactory.create(activity)
            manager.requestReviewFlow().addOnCompleteListener(activity) { task ->
                if (task.isSuccessful && canPresent() && activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                    try { manager.launchReviewFlow(activity, task.result) } catch (_: Exception) { }
                }
            }
        } catch (_: Exception) { }
    }

    private fun update(next: ReviewPolicy) {
        if (next == state) return
        state = next
        persist()
    }

    private fun persist() {
        prefs.edit()
            .putLong("tracked_end", state.trackedEndAtMs ?: 0)
            .putLong("ready_end", state.readyEndAtMs ?: 0)
            .putLong("handled_end", state.handledEndAtMs)
            .putLong("last_request", state.lastRequestAtMs)
            .putBoolean("disabled", state.disabled)
            .commit()
    }

    companion object {
        @Volatile private var shared: ReviewCoordinator? = null

        fun get(context: Context): ReviewCoordinator = shared ?: synchronized(this) {
            shared ?: ReviewCoordinator(context).also { shared = it }
        }
    }
}
