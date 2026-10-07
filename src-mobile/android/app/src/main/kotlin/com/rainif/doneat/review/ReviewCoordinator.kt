package com.rainif.doneat.review

import android.content.Context
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import com.google.android.play.core.review.ReviewManagerFactory
import com.rainif.doneat.BuildConfig
import java.time.ZoneId
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Device-local request state. The backup include list excludes SharedPreferences. */
class ReviewCoordinator private constructor(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("play_review", Context.MODE_PRIVATE)
    private var state = ReviewPolicy(
        completedDays = prefs.getInt("completed_days", 0).coerceAtLeast(0),
        lastCompletedDayKey = prefs.getString("last_completed_day", null),
        lastRequestVersion = prefs.getString("last_request_version", null),
        // Preserve old throttling and opt-out, but never promote old tracked/ready ends into completions.
        lastRequestAtMs = prefs.getLong("last_request", 0),
        disabled = prefs.getBoolean("disabled", false),
    )
    private val mutableOffers = MutableStateFlow(0L)
    val offers = mutableOffers.asStateFlow()
    private var pendingOffer: ReviewOffer? = null
    private var requestGeneration = 0L

    init { persist() }

    /** Call for a real started shift's completed surface; never infer completion at startup. */
    @Synchronized
    fun noteCompletion(endAtMs: Long, recordsZone: ZoneId) =
        update(state.completed(ReviewPolicy.dayKey(endAtMs, recordsZone)))

    /** Call once as the automatic clock-off celebration starts, never on manual replay. */
    @Synchronized
    fun offerAfterCelebration(endAtMs: Long, nowMs: Long = System.currentTimeMillis()) {
        if (!state.canOffer(endAtMs, BuildConfig.VERSION_NAME, nowMs)) return
        val id = mutableOffers.value + 1
        pendingOffer = ReviewOffer(id, nowMs)
        mutableOffers.value = id
    }

    /** An editor, navigation or loss of foreground drops the moment instead of deferring it. */
    @Synchronized
    fun discardOffer(offerId: Long) {
        if (mutableOffers.value != offerId) return
        pendingOffer = null
        requestGeneration++
    }

    /** Undo or extra overtime means the former end was not the final clock-off. */
    @Synchronized
    fun revokeCompletion(endAtMs: Long, recordsZone: ZoneId) {
        clearTrackedCompletion()
        update(state.revoked(ReviewPolicy.dayKey(endAtMs, recordsZone)))
    }

    /** Canceling a manual run discards an outstanding request. No projected end is persisted. */
    @Synchronized
    fun clearTrackedCompletion() {
        pendingOffer = null
        requestGeneration++
    }

    /** The manual Settings link remains usable after automatic requests stop. */
    @Synchronized
    fun disableAutomatic() {
        clearTrackedCompletion()
        update(state.disable())
    }

    /** Root waits six seconds after [offers], dropping the offer whenever presentation is blocked. */
    fun requestIfEligible(activity: FragmentActivity, offerId: Long, canPresent: () -> Boolean) {
        val now = System.currentTimeMillis()
        val generation: Long
        synchronized(this) {
            val offer = pendingOffer?.takeIf { it.id == offerId } ?: return
            if (!canPresent() || !activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                discardOffer(offerId)
                return
            }
            if (!offer.hasSettled(now)) return
            pendingOffer = null
            if (!state.isDue(BuildConfig.VERSION_NAME, now)) return
            generation = ++requestGeneration
            update(state.requested(BuildConfig.VERSION_NAME, now))
        }
        // Play may silently suppress the card. A failed request is equally silent and consumed.
        try {
            val manager = ReviewManagerFactory.create(activity)
            manager.requestReviewFlow().addOnCompleteListener(activity) { task ->
                synchronized(this) {
                    if (task.isSuccessful && generation == requestGeneration && !state.disabled &&
                        canPresent() && activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
                    ) {
                        try { manager.launchReviewFlow(activity, task.result) } catch (_: Exception) { }
                    }
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
