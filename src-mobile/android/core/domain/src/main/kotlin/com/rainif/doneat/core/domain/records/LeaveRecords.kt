package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.LeavePortion
import com.rainif.doneat.core.domain.schedule.SwiftText

/**
 * Plan 020's leave records (iOS `LeaveBalance` / `LeaveDay`, schema 7): the
 * pots of leave the user tracks and the days adopted plans took. Rows keep
 * exactly what iOS wrote, so a backup round trip never changes them.
 *
 * Amounts are whole half days. A day's `uses` either is empty or adds up to its
 * portion; a balance's validity window is inclusive and ordered.
 */
data class LeaveBalance(
    val id: String,
    /** `annual`, `compensatory` or `custom`; iOS reads any other kind as custom. */
    val kind: String,
    val name: String?,
    val entitledHalfDays: Int,
    val usedHalfDays: Int,
    val validFromDayKey: String?,
    val validThroughDayKey: String?,
    val editedAtMs: Double,
    val editCount: Int,
    val editTieBreaker: String,
) {
    /** What the planner may still spend, before any adopted plan is deducted. */
    val remainingHalfDays get() = maxOf(0, entitledHalfDays - usedHalfDays)

    /** The planner's view of this balance, less [adoptedHalfDays] already committed by adopted plans. */
    fun budget(adoptedHalfDays: Int = 0): LeaveBudget? {
        if (!isValid) return null
        return LeaveBudget(
            id = id,
            availableHalfDays = maxOf(0, remainingHalfDays - adoptedHalfDays),
            validFromDayNumber = validFromDayKey?.let(ExtendedScheduleResolver::dayNumber),
            validThroughDayNumber = validThroughDayKey?.let(ExtendedScheduleResolver::dayNumber),
        )
    }

    val isValid: Boolean
        get() {
            val trimmed = name?.let(SwiftText::trimWhitespaceAndNewlines).orEmpty()
            val from = validFromDayKey?.let { ExtendedScheduleResolver.dayNumber(it) ?: return false }
            val through = validThroughDayKey?.let { ExtendedScheduleResolver.dayNumber(it) ?: return false }
            if (from != null && through != null && from > through) return false
            return entitledHalfDays in 0..MAXIMUM_HALF_DAYS &&
                usedHalfDays in 0..MAXIMUM_HALF_DAYS &&
                SwiftText.characterCount(trimmed) <= MAXIMUM_NAME_LENGTH &&
                editCount >= 0 &&
                (kind != CUSTOM || trimmed.isNotEmpty())
        }

    companion object {
        const val MAXIMUM_NAME_LENGTH = 40
        const val MAXIMUM_HALF_DAYS = 2 * 366 * 10
        const val CUSTOM = "custom"
        private val KINDS = setOf("annual", "compensatory", CUSTOM)

        /** A kind a newer build added reads as custom, as iOS decodes it. */
        fun normalizedKind(raw: String) = if (raw in KINDS) raw else CUSTOM
    }
}

/** Spendable half days and the civil days they may be spent on. */
data class LeaveBudget(
    val id: String,
    val availableHalfDays: Int,
    val validFromDayNumber: Int? = null,
    val validThroughDayNumber: Int? = null,
) {
    fun covers(dayNumber: Int) =
        (validFromDayNumber?.let { dayNumber >= it } ?: true) && (validThroughDayNumber?.let { dayNumber <= it } ?: true)
}

data class LeaveBalanceUse(val balanceID: String, val halfDays: Int)

data class LeaveDay(
    val dayKey: String,
    /** `whole`, `firstHalf` or `secondHalf`. */
    val portion: String,
    val uses: List<LeaveBalanceUse>,
    val planID: String?,
    val timeZoneIdentifier: String,
    val editedAtMs: Double,
    val editCount: Int,
    val editTieBreaker: String,
) {
    /** The portion as the rules read it; a row that fails [isValid] has none. */
    val leavePortion: LeavePortion? get() = LeavePortion.fromRaw(portion)

    val isValid: Boolean
        get() {
            val halfDays = PORTION_HALF_DAYS[portion] ?: return false
            val total = uses.sumOf { it.halfDays }
            return ExtendedScheduleResolver.parse(dayKey) != null &&
                FoundationCompat.isValidTimeZone(timeZoneIdentifier) &&
                uses.all { it.halfDays > 0 } &&
                uses.map { it.balanceID }.toSet().size == uses.size &&
                (total == 0 || total == halfDays) &&
                editCount >= 0
        }

    companion object {
        val PORTION_HALF_DAYS = mapOf("whole" to 2, "firstHalf" to 1, "secondHalf" to 1)
    }
}

/** Half days adopted plans have spent from each balance. */
fun List<LeaveDay>.adoptedHalfDays(): Map<String, Int> {
    val spent = HashMap<String, Int>()
    for (day in this) for (use in day.uses) spent.merge(use.balanceID, use.halfDays, Int::plus)
    return spent
}

/** Each valid row's portion by day key, first row per key, as the rules read leave. */
fun List<LeaveDay>.portionsByDay(): Map<String, LeavePortion> {
    val map = LinkedHashMap<String, LeavePortion>()
    for (day in this) {
        if (day.dayKey in map) continue
        day.leavePortion?.let { map[day.dayKey] = it }
    }
    return map
}
