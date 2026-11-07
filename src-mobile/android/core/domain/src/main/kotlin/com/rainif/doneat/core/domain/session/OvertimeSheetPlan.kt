package com.rainif.doneat.core.domain.session

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Plan 024 phase 4: the rests the overtime sheet offers before the overtime
 * begins (dinner, say). They are breaks, not overtime (iOS `OvertimeRestChoices`).
 */
object OvertimeRestChoices {
    val minutes = listOf(0, 15, 30, 45, 60)

    /** The choice closest to [minutes], for prefilling a sheet from a session. */
    fun nearest(minutes: Double): Int = this.minutes.minByOrNull { abs(it - minutes) } ?: 0
}

/**
 * Plan 024: the overtime pay multiplier choices the overtime sheet and the
 * salary settings share (iOS `OvertimePayChoices`). The rule itself is `OvertimePay`.
 */
object OvertimePayChoices {
    /** Offered directly; anything else is entered with the stepper. */
    val presets = listOf(1.0, 1.5, 2.0, 3.0)

    /** The stepper's range, in tenths. */
    val customTenths = 5..50

    fun isPreset(multiplier: Double) = multiplier in presets
    fun tenths(multiplier: Double) = (multiplier * 10).roundToInt()
    fun multiplier(tenths: Int) = tenths / 10.0
}

/**
 * What the overtime sheet has chosen so far, and the instants and figures that
 * follow from it (iOS `OvertimeSheetPlan`). Pure, so the sheet and its tests
 * read the same rules: the overtime starts at the planned clock-off plus the
 * rest, and the counted hours are the time from that start to the end.
 */
data class OvertimeSheetPlan(
    val plannedEndMs: Double,
    val nowMs: Double,
    val entry: Entry = Entry.UNTIL,
    val restMinutes: Int = 0,
    val untilMs: Double,
    val durationMinutes: Int = 60,
) {
    enum class Entry {
        /** Pick the clock time the overtime ends. */
        UNTIL,

        /** Pick how long it lasts, after the rest. */
        DURATION,
    }

    /** When the overtime itself starts: after the rest. */
    val startMs: Double get() = plannedEndMs + restMinutes * 60_000.0

    val endMs: Double
        get() = when (entry) {
            Entry.UNTIL -> untilMs
            Entry.DURATION -> startMs + durationMinutes * 60_000.0
        }

    /** An end cannot precede the overtime's start or now; after a rest it must leave a minute of overtime. */
    val minimumEndMs: Double get() = max(if (restMinutes > 0) startMs + 60_000 else startMs, nowMs)

    /** What the session receives as the start: only a rest moves it. */
    val overtimeStartMs: Double? get() = if (restMinutes > 0) startMs else null

    val isValid: Boolean get() = endMs >= minimumEndMs

    /** Counted milliseconds: the end minus the start, never negative. */
    val countedMs: Double get() = max(0.0, endMs - startMs)

    /** Durations that still end now or later, 15 minutes apart. */
    val durationChoices: List<Int>
        get() {
            val step = DURATION_STEP_MINUTES
            val elapsed = max(0.0, (nowMs - startMs) / 60_000)
            val first = max(step, ceil(elapsed / step).toInt() * step)
            return (first..max(first, MAXIMUM_DURATION_MINUTES) step step).toList()
        }

    private fun closestDuration(endMs: Double): Int {
        val minutes = (endMs - startMs) / 60_000
        return durationChoices.minByOrNull { abs(it - minutes) } ?: DURATION_STEP_MINUTES
    }

    /** Switches between the two ways of choosing, keeping the same end. */
    fun selecting(next: Entry): OvertimeSheetPlan {
        if (next == entry) return this
        return if (next == Entry.DURATION) {
            copy(entry = next, durationMinutes = closestDuration(untilMs))
        } else {
            copy(entry = next, untilMs = max(endMs, minimumEndMs))
        }
    }

    /** Keeps the choices valid after the rest or the clock moved. */
    fun settled(): OvertimeSheetPlan = when (entry) {
        Entry.UNTIL -> copy(untilMs = max(untilMs, minimumEndMs))
        Entry.DURATION -> {
            val choices = durationChoices
            copy(durationMinutes = durationMinutes.coerceIn(choices.first(), choices.last()))
        }
    }

    companion object {
        const val DURATION_STEP_MINUTES = 15
        const val MAXIMUM_DURATION_MINUTES = 12 * 60
    }
}
