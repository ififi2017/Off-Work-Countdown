package com.rainif.doneat.review

import java.time.Instant
import java.time.ZoneId

/**
 * A surface that must not share the screen with the system review card.
 * Editors, the schedule editor, focus and other pages or dialogs defer the
 * same way the paywall does: the open is not today's attempt.
 */
internal enum class ReviewBlocker {
    NONE,
    PAYWALL,
    LIFETIME_GIFT,
    WHATS_NEW,
    EDITOR,
    SCHEDULE,
    FOCUS,
    DIALOG,
}

/**
 * Which returns to the foreground start a visit. A cold start still does:
 * [backgrounded] begins set. Rotation does not, and neither does a start
 * that never went through [onStop]. Leaving during the settle wait does not
 * decide the visit.
 */
internal data class ReviewVisits(
    val generation: Int = 0,
    val backgrounded: Boolean = true,
    val decided: Int = 0,
) {
    fun onStart(): ReviewVisits =
        if (!backgrounded) this else copy(generation = generation + 1, backgrounded = false)

    /** A configuration change recreates the activity without leaving the app. */
    fun onStop(changingConfigurations: Boolean): ReviewVisits =
        if (changingConfigurations || backgrounded) this else copy(backgrounded = true)

    /**
     * The settle wait ended. [stillInForeground] is false when the user left
     * during those six seconds: the visit stays undecided and is not an attempt.
     * The same visit may still be decided if it becomes foreground again.
     */
    fun onSettled(visit: Int, stillInForeground: Boolean): Pair<ReviewVisits, Boolean> {
        if (!stillInForeground || visit != generation || visit <= decided) return this to false
        return copy(decided = visit) to true
    }
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
     * After today's off-work time, the first foreground with nothing else on
     * screen. A blocked open stays unattempted so the next qualifying
     * foreground can ask. At most one attempt per records-calendar day.
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

        /** As on iOS, completion and "today" use Records' calendar, including overnight shifts. */
        fun dayKey(endAtMs: Long, recordsZone: ZoneId): String =
            Instant.ofEpochMilli(endAtMs).atZone(recordsZone).toLocalDate().toString()

        /** [todayKey] is the records day of [nowMs]. The finished day is counted only once off-work is past. */
        fun foreground(nowMs: Long, offWorkAtMs: Long?, recordsZone: ZoneId, blocker: ReviewBlocker = ReviewBlocker.NONE) =
            ReviewForeground(
                nowMs = nowMs,
                todayKey = dayKey(nowMs, recordsZone),
                offWorkAtMs = offWorkAtMs,
                finishedShiftDayKey = offWorkAtMs?.takeIf { nowMs >= it }?.let { dayKey(it, recordsZone) },
                blocker = blocker,
            )
    }
}
