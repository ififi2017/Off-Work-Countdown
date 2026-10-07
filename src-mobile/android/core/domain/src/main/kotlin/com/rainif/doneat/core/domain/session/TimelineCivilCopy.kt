package com.rainif.doneat.core.domain.session

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId

/** Civil-date copy for preview rows; never resolves or invents a future shift. */
object TimelineCivilCopy {
    const val TODAY = "todaysShift"
    const val CURRENT_MONTH = "scheduleCurrentMonthActive"
    const val NEXT_MONTH = "scheduleNextMonthPlanned"

    private fun date(atMs: Double, zone: ZoneId) = Instant.ofEpochMilli(atMs.toLong()).atZone(zone).toLocalDate()

    /** A caller must already know this date has a scheduled shift. */
    fun knownRosterStatusKey(startAtMs: Double, nowMs: Double, zone: ZoneId, known: Boolean): String? {
        if (!known) return null
        val current = YearMonth.from(date(nowMs, zone))
        return when (YearMonth.from(date(startAtMs, zone))) {
            current -> CURRENT_MONTH
            current.plusMonths(1) -> NEXT_MONTH
            else -> null
        }
    }

    fun startDetailKey(startAtMs: Double, nowMs: Double, zone: ZoneId, knownRosterStatusKey: String? = null): String? =
        if (date(startAtMs, zone) == date(nowMs, zone)) TODAY else knownRosterStatusKey

    /** Only an end row for this still-live shift may describe today's shift. */
    fun endDetailKey(
        eventEndAtMs: Double,
        currentStartAtMs: Double,
        currentEndAtMs: Double,
        endedEarly: Boolean,
        nowMs: Double,
        zone: ZoneId,
    ): String? = TODAY.takeIf {
        !endedEarly && currentEndAtMs > nowMs && eventEndAtMs == currentEndAtMs &&
            date(currentStartAtMs, zone) == date(nowMs, zone)
    }
}
