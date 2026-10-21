package com.rainif.doneat.review

import android.content.Context
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import com.google.android.play.core.review.ReviewManagerFactory
import com.rainif.doneat.BuildConfig
import com.rainif.doneat.core.domain.schedule.ShiftSnapshot
import com.rainif.doneat.core.domain.session.ShiftSession
import java.time.ZoneId
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Device-local request state. The backup include list excludes SharedPreferences. */
class ReviewCoordinator private constructor(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences("play_review", Context.MODE_PRIVATE)
    private var state = ReviewPolicy(
        completedDays = prefs.getInt("completed_days", 0).coerceAtLeast(0),
        lastCompletedDayKey = prefs.getString("last_completed_day", null),
        lastRequestVersion = prefs.getString("last_request_version", null),
        // Preserve old throttling and opt-out, but never promote old tracked/ready ends into completions.
        lastRequestAtMs = prefs.getLong("last_request", 0),
        lastAttemptDayKey = prefs.getString("last_attempt_day", null),
        disabled = prefs.getBoolean("disabled", false),
    )
    private val foregroundTicks = MutableStateFlow(0)
    /** Bumped from [android.app.Activity.onResume]. The UI reads it once per return to the foreground. */
    val foreground = foregroundTicks.asStateFlow()

    init { persist() }

    /** Call for a real started shift's completed surface; never infer completion at startup. */
    @Synchronized
    fun noteCompletion(endAtMs: Long, recordsZone: ZoneId) =
        update(state.completed(ReviewPolicy.dayKey(endAtMs, recordsZone)))

    /** Undo or extra overtime means the former end was not the final clock-off. */
    @Synchronized
    fun revokeCompletion(endAtMs: Long, recordsZone: ZoneId) {
        update(state.revoked(ReviewPolicy.dayKey(endAtMs, recordsZone)))
    }

    /** The manual Settings link remains usable after automatic requests stop. */
    @Synchronized
    fun disableAutomatic() = update(state.disable())

    fun noteForeground() {
        foregroundTicks.value = foregroundTicks.value + 1
    }

    /**
     * Decides and, when asking, records the attempt before Play is called.
     * A suppressed or failed card must not be retried on the next resume.
     */
    @Synchronized
    fun consumeForeground(event: ReviewForeground): Boolean {
        val outcome = if (BuildConfig.DEBUG) {
            ReviewDebugGate.intercept(appContext, state, event)
                ?: state.onForeground(event, BuildConfig.VERSION_NAME)
        } else {
            state.onForeground(event, BuildConfig.VERSION_NAME)
        }
        if (outcome.policy != state) update(outcome.policy)
        return outcome.request
    }

    /** Play may silently suppress the card. A failed request is equally silent and already consumed. */
    fun launchReview(activity: FragmentActivity) {
        if (!activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) return
        try {
            val manager = ReviewManagerFactory.create(activity)
            manager.requestReviewFlow().addOnCompleteListener(activity) { task ->
                if (task.isSuccessful && activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
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
            .remove("tracked_end").remove("ready_end").remove("handled_end")
            .putInt("completed_days", state.completedDays)
            .putString("last_completed_day", state.lastCompletedDayKey)
            .putString("last_request_version", state.lastRequestVersion)
            .putLong("last_request", state.lastRequestAtMs)
            .putString("last_attempt_day", state.lastAttemptDayKey)
            .putBoolean("disabled", state.disabled)
            .commit()
    }

    companion object {
        @Volatile private var shared: ReviewCoordinator? = null

        fun get(context: Context): ReviewCoordinator = shared ?: synchronized(this) {
            shared ?: ReviewCoordinator(context).also { shared = it }
        }

        /** Today's off-work instant, or null when this day has no shift to finish. */
        fun offWorkAtMs(session: ShiftSession, nowMs: Double): Long? {
            if (!session.shouldQuerySnapshot(nowMs)) return null
            val shift = session.snapshot(nowMs) ?: return null
            return offWorkAtMs(shift, session.isForcedWorkday(shift), session.isEndedEarly(shift), session.state.earlyOffAtMs)
        }

        fun offWorkAtMs(shift: ShiftSnapshot, forcedWorkday: Boolean, endedEarly: Boolean, earlyOffAtMs: Double?): Long? {
            val worked = (shift.isWorkday || forcedWorkday || endedEarly) && shift.segments.isNotEmpty()
            if (!worked) return null
            val end = if (endedEarly) earlyOffAtMs ?: shift.plannedEndAtMs else shift.endAtMs
            return end.toLong()
        }

        fun foregroundEvent(session: ShiftSession, nowMs: Double, blocker: ReviewBlocker): ReviewForeground {
            val offWorkAtMs = offWorkAtMs(session, nowMs)
            val now = nowMs.toLong()
            val finished = offWorkAtMs?.takeIf { now >= it }?.let { ReviewPolicy.dayKey(it, session.recordsZone) }
            return ReviewForeground(
                nowMs = now,
                todayKey = ReviewPolicy.dayKey(now, session.recordsZone),
                offWorkAtMs = offWorkAtMs,
                finishedShiftDayKey = finished,
                blocker = blocker,
            )
        }
    }
}
