package com.rainif.doneat.core.domain.schedule

import com.rainif.doneat.core.domain.salary.JavaScriptNumber
import java.math.BigDecimal
import kotlin.math.abs
import kotlin.math.ceil

/**
 * One shift's reminders with their absolute trigger times and final copy
 * (`buildShiftReminders` in `lib/reminders.ts`, iOS `ReminderRules`).
 *
 * `lib/reminders.ts` is the specification and the shared fixtures hold this
 * port to it. A reminder whose switch is off is still listed, with no title
 * or body, so turning a switch on mid-shift does not replay the ones already
 * crossed.
 */
object ReminderRules {
    /** A break-boundary push that fires this late has lost its context. */
    private const val BREAK_FRESHNESS_MS = 2.0 * 60_000
    /** A micro-break after a longer gap means the device slept through the work it asks the user to rest from. */
    private const val MICRO_BREAK_MAX_TICK_GAP_MS = 2.0 * 60_000
    /** Keeps a one-minute interval from exhausting the pending-alarm budget. */
    private const val MAX_MICRO_BREAKS_PER_SEGMENT = 240
    private const val DEFAULT_TITLE = "Off work reminder"

    private val defaultBodies = mapOf(
        50 to "Halfway there.",
        75 to "The hardest part is behind you.",
        90 to "Almost there.",
        95 to "Just a little longer.",
        100 to "Off work time!",
    )

    fun buildShiftReminders(shift: ShiftTimeline, inputs: ReminderInputs): List<Reminder> {
        val durationMs = shift.durationMs
        if (!shift.isValid || durationMs <= 0) return emptyList()
        val endAtMs = shift.endAtMs
        val reminders = ArrayList<Reminder>()

        for ((percent, defaultBody) in defaultBodies) {
            val thresholdMs = ceil(durationMs * percent / 100)
            val cycleEndSummary = if (percent == 100) nonEmpty(inputs.cycleEndSummaryBody?.let(JavaScriptNumber::trim)) else null
            val audible = cycleEndSummary != null || inputs.mode == "milestones" || (inputs.mode == "simple" && percent == 100)
            reminders += Reminder(
                id = "milestone:$percent",
                kind = ReminderKind.MILESTONE,
                atMs = absoluteAtElapsedMs(shift, thresholdMs),
                expiresAtMs = null,
                maxTickGapMs = null,
                collapseGroup = "milestone",
                title = if (audible) nonEmpty(inputs.milestoneTitles[percent]) ?: nonEmpty(inputs.fallbackTitle) ?: DEFAULT_TITLE else null,
                body = if (audible) cycleEndSummary ?: milestoneBody(inputs.milestoneMessages[percent].orEmpty(), percent, defaultBody, endAtMs) else null,
            )
        }

        val breakTitle = nonEmpty(inputs.breakTitle) ?: nonEmpty(inputs.fallbackTitle) ?: DEFAULT_TITLE
        val segments = shift.segments
        for (index in 0 until segments.size - 1) {
            val breakStartAtMs = segments[index].endAtMs
            val breakEndAtMs = segments[index + 1].startAtMs
            if (breakEndAtMs <= breakStartAtMs) continue

            val startBody = if (inputs.lunchStartEnabled) nonEmpty(inputs.lunchStartBody) else null
            reminders += Reminder(
                id = "breakStart:${jsString(breakStartAtMs)}",
                kind = ReminderKind.BREAK_START,
                atMs = breakStartAtMs,
                // A break that is already over is not starting.
                expiresAtMs = minOf(breakStartAtMs + BREAK_FRESHNESS_MS, breakEndAtMs),
                maxTickGapMs = null,
                collapseGroup = "break",
                title = startBody?.let { breakTitle },
                body = startBody,
            )

            val endBody = if (inputs.lunchEndEnabled) nonEmpty(inputs.lunchEndBody) else null
            reminders += Reminder(
                id = "breakEnd:${jsString(breakEndAtMs)}",
                kind = ReminderKind.BREAK_END,
                atMs = breakEndAtMs,
                expiresAtMs = minOf(breakEndAtMs + BREAK_FRESHNESS_MS, segments[index + 1].endAtMs),
                maxTickGapMs = null,
                collapseGroup = "break",
                title = endBody?.let { breakTitle },
                body = endBody,
            )
        }

        val intervalMinutes = maxOf(0, inputs.microBreakIntervalMinutes)
        val intervalMs = intervalMinutes * 60_000.0
        if (intervalMs > 0) {
            for (segment in segments) {
                // Each segment restarts the count: a round cut short by lunch does not carry over.
                val start = jsString(segment.startAtMs)
                for (bucket in 1..MAX_MICRO_BREAKS_PER_SEGMENT) {
                    val atMs = segment.startAtMs + bucket * intervalMs
                    if (atMs >= segment.endAtMs) break
                    val body = if (inputs.microBreakEnabled) microBreakBody(inputs.microBreakMessages, bucket, intervalMinutes) else null
                    reminders += Reminder(
                        id = "microBreak:$start:$bucket",
                        kind = ReminderKind.MICRO_BREAK,
                        atMs = atMs,
                        expiresAtMs = null,
                        maxTickGapMs = MICRO_BREAK_MAX_TICK_GAP_MS,
                        collapseGroup = "microBreak:$start",
                        title = body?.let { nonEmpty(inputs.microBreakTitle) ?: breakTitle },
                        body = body,
                    )
                }
            }
        }
        return sortedByTime(reminders)
    }

    /** Stable, as `Array.prototype.sort` is: equal instants keep list order. */
    fun sortedByTime(reminders: List<Reminder>) = reminders.sortedBy { it.atMs }

    /** `String(number)` for millisecond instants: whole numbers bare, anything else in shortest form. */
    fun jsString(value: Double): String =
        if (value == Math.floor(value) && abs(value) < 9e15) value.toLong().toString() else BigDecimal(value.toString()).toPlainString()

    /** Wall-clock instant at which [elapsedMs] of effective work has passed; a segment's end fires there, not after the gap. */
    private fun absoluteAtElapsedMs(shift: ShiftTimeline, elapsedMs: Double): Double {
        var remaining = elapsedMs
        for (segment in shift.segments) {
            val duration = segment.endAtMs - segment.startAtMs
            if (remaining <= duration) return segment.startAtMs + remaining
            remaining -= duration
        }
        return shift.segments.last().endAtMs
    }

    /** Seeded by the shift's end so a pending notification keeps its wording every time the list is rebuilt. */
    private fun milestoneBody(pool: List<String>, percent: Int, defaultBody: String, endAtMs: Double): String? {
        if (pool.isEmpty()) return defaultBody
        val index = (abs(endAtMs) + percent) % pool.size
        // A fractional end (overtime stopped mid-millisecond) indexes nothing in the TypeScript either.
        if (index != Math.floor(index)) return null
        return pool[index.toInt()]
    }

    private fun microBreakBody(pool: List<String>, bucket: Int, intervalMinutes: Int): String? {
        if (pool.isEmpty()) return null
        val template = nonEmpty(pool[bucket % pool.size]) ?: return null
        // `String.prototype.replace` with a string pattern: first occurrence only.
        return template.replaceFirst("{{minutes}}", (bucket * intervalMinutes).toString())
    }

    private fun nonEmpty(value: String?) = value?.takeIf { it.isNotEmpty() }
}

enum class ReminderKind(val raw: String) { MILESTONE("milestone"), BREAK_START("breakStart"), BREAK_END("breakEnd"), MICRO_BREAK("microBreak") }

data class Reminder(
    /** Stable across rebuilds and unique in one list; the scheduler keys system alarms on it. */
    val id: String,
    val kind: ReminderKind,
    val atMs: Double,
    /** Half-open validity `[atMs, expiresAtMs)`; null never expires. */
    val expiresAtMs: Double?,
    val maxTickGapMs: Double?,
    val collapseGroup: String?,
    /** Null title and body: the reminder only advances dedupe state (its switch is off). */
    val title: String?,
    val body: String?,
) {
    val isAudible get() = title != null && body != null
}

data class ReminderInputs(
    val mode: String,
    val fallbackTitle: String,
    /** Title for lunch start and end; without it lunch pushes would read as the off-work title. */
    val breakTitle: String,
    /** Keyed by milestone percent: 50, 75, 90, 95, 100. */
    val milestoneTitles: Map<Int, String>,
    val milestoneMessages: Map<Int, List<String>>,
    val lunchStartEnabled: Boolean,
    val lunchStartBody: String,
    val lunchEndEnabled: Boolean,
    val lunchEndBody: String,
    val microBreakEnabled: Boolean,
    val microBreakTitle: String,
    val microBreakIntervalMinutes: Int,
    /** `{{minutes}}` becomes the minutes worked in the segment so far. */
    val microBreakMessages: List<String>,
    /** Replaces the 100% copy when this shift ends a run of workdays; null when it does not. */
    val cycleEndSummaryBody: String?,
)
