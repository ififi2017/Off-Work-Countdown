package com.rainif.doneat.review

import java.time.Instant
import java.time.ZoneId

/** A full-screen layer that must not share the screen with the system review card. */
internal enum class ReviewBlocker {
    NONE,
    PAYWALL,
    LIFETIME_GIFT,
    WHATS_NEW,
}

/**
 * One return to the foreground. [offWorkAtMs] is today's shift end, or null on a
 * rest day. [finishedShiftDayKey] is set only once that end is already in the past,
 * so the open that follows clock-off can count the day before the due check.
 */
internal data class ReviewForeground(
    val nowMs: Long,
    val todayKey: String,
    val offWorkAtMs: Long?,
    val finishedShiftDayKey: String?,
    val blocker: ReviewBlocker,
)

internal data class ReviewForegroundResult(val policy: ReviewPolicy, val request: Boolean)

/** Durable device-local eligibility, matching iOS AppReviewPromptState. */
internal data class ReviewPolicy(
    val completedDays: Int = 0,
    val lastCompletedDayKey: String? = null,
    val lastRequestVersion: String? = null,
    val lastRequestAtMs: Long = 0,
    /** Records-calendar day of the last real review attempt. A blocked open does not set it. */
    val lastAttemptDayKey: String? = null,
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

    /**
     * After today's off-work time, the first foreground that is actually free of
     * the paywall, lifetime gift and What's New. A blocked open stays unattempted
     * so the next qualifying foreground can ask. At most one attempt per day.
     */
    fun onForeground(event: ReviewForeground, version: String): ReviewForegroundResult {
        val counted = countingFinishedShift(event)
        if (event.blocker != ReviewBlocker.NONE) return ReviewForegroundResult(counted, false)
        val offWorkAtMs = event.offWorkAtMs
        if (offWorkAtMs == null || event.nowMs < offWorkAtMs) return ReviewForegroundResult(counted, false)
        if (counted.lastAttemptDayKey == event.todayKey) return ReviewForegroundResult(counted, false)
        if (!counted.isDue(version, event.nowMs)) return ReviewForegroundResult(counted, false)
        return ReviewForegroundResult(
            counted.requested(version, event.nowMs).copy(lastAttemptDayKey = event.todayKey),
            true,
        )
    }

    /** Consume before calling Play: a quota-suppressed or failed request must not loop. */
    fun requested(currentVersion: String, nowMs: Long) = copy(
        completedDays = 0,
        lastRequestVersion = currentVersion,
        lastRequestAtMs = nowMs,
    )

    fun disable() = copy(disabled = true)

    internal fun countingFinishedShift(event: ReviewForeground): ReviewPolicy {
        val day = event.finishedShiftDayKey ?: return this
        val offWorkAtMs = event.offWorkAtMs ?: return this
        if (event.nowMs < offWorkAtMs) return this
        return completed(day)
    }

    companion object {
        const val MINIMUM_COMPLETED_DAYS = 2
        const val REQUEST_GAP_MS = 120L * 24 * 60 * 60 * 1_000
        /** Never over the first frame of a visit, nor over the five-second clock-off celebration. */
        const val FOREGROUND_SETTLE_MS = 6_000L

        /** As on iOS, completion uses Records' calendar, including overnight shifts. */
        fun dayKey(endAtMs: Long, recordsZone: ZoneId): String =
            Instant.ofEpochMilli(endAtMs).atZone(recordsZone).toLocalDate().toString()
    }
}
