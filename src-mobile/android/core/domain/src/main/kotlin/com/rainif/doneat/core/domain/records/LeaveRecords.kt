package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.SwiftText

/**
 * Plan 020's leave records (iOS `LeaveBalance` / `LeaveDay`, schema 7). Android
 * has no leave planning yet: the archive keeps these rows exactly as iOS wrote
 * them so a backup round trip never drops them.
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
