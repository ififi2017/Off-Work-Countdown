package com.rainif.doneat.review

import java.time.Instant
import java.time.ZoneId

/** Durable device-local eligibility, matching iOS 3.2.1 AppReviewPromptState. */
internal data class ReviewPolicy(
    val completedDays: Int = 0,
    val lastCompletedDayKey: String? = null,
    val lastRequestVersion: String? = null,
    val lastRequestAtMs: Long = 0,
    val disabled: Boolean = false,
) {
    fun completed(dayKey: String): ReviewPolicy =
        if (disabled || dayKey == lastCompletedDayKey) this
        else copy(completedDays = completedDays + 1, lastCompletedDayKey = dayKey)

    /** Continuing that day's work removes its completion; finishing later can count it again. */
    fun revoked(dayKey: String): ReviewPolicy =
        if (dayKey != lastCompletedDayKey || completedDays <= 0) this
        else copy(completedDays = completedDays - 1, lastCompletedDayKey = null)

    fun isDue(currentVersion: String, nowMs: Long): Boolean =
        !disabled && completedDays >= MINIMUM_COMPLETED_DAYS &&
            lastRequestVersion != currentVersion &&
            (lastRequestAtMs == 0L || nowMs - lastRequestAtMs >= REQUEST_GAP_MS)

    /** Only a celebration of the actual clock-off moment may offer a request. */
    fun canOffer(endAtMs: Long, currentVersion: String, nowMs: Long): Boolean =
        nowMs >= endAtMs - COMPLETION_WINDOW_MS && nowMs <= endAtMs + COMPLETION_WINDOW_MS &&
            isDue(currentVersion, nowMs)

    /** Consume before calling Play: a quota-suppressed or failed request must not loop. */
    fun requested(currentVersion: String, nowMs: Long) = copy(
        completedDays = 0,
        lastRequestVersion = currentVersion,
        lastRequestAtMs = nowMs,
    )

    fun disable() = copy(disabled = true)

    companion object {
        const val MINIMUM_COMPLETED_DAYS = 3
        const val REQUEST_GAP_MS = 120L * 24 * 60 * 60 * 1_000
        const val COMPLETION_WINDOW_MS = 2L * 60 * 1_000
        const val CELEBRATION_SETTLE_MS = 6_000L

        /** As on iOS, completion uses Records' calendar, including overnight shifts. */
        fun dayKey(endAtMs: Long, recordsZone: ZoneId): String =
            Instant.ofEpochMilli(endAtMs).atZone(recordsZone).toLocalDate().toString()
    }
}

/** In-memory only: launch never restores a request from a prior completion. */
internal data class ReviewOffer(val id: Long, val offeredAtMs: Long) {
    fun hasSettled(nowMs: Long): Boolean = nowMs - offeredAtMs >= SETTLE_DELAY_MS

    companion object {
        const val SETTLE_DELAY_MS = ReviewPolicy.CELEBRATION_SETTLE_MS
    }
}
