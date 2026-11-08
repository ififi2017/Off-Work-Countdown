package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.SwiftText

/**
 * Plan 021 C1's provenance of adopted workplace times (iOS `WorkTimeProvenance`,
 * schema 8): one row per records day saying how automation arrived at that
 * day's adopted start or end. Android 3.3.0 has no workplace automation; it
 * only reads these rows and writes them back exactly as iOS wrote them, so a
 * backup round trip through Android never loses or changes them.
 *
 * Rows carry no coordinates, Wi-Fi names, place names or geofence identifiers.
 * Enum-like fields stay strings; a value a newer build adds rejects its row.
 */
data class WorkTimeProvenance(
    val dayKey: String,
    val boundaries: List<Boundary>,
    val timeZoneIdentifier: String,
    val editedAtMs: Double,
    val editCount: Int,
    val editTieBreaker: String,
) {
    data class Boundary(
        /** `start` or `end`. */
        val boundary: String,
        val timeMs: Double,
        /** `nativeGeofence`, `appIntentAutomation` or `userConfirmation`. */
        val source: String,
        val observedAtMs: Double?,
        val receivedAtMs: Double,
        val appliedAtMs: Double,
        /** `automatic` or `reviewed`. */
        val appliedBy: String,
        val batchID: String?,
        val rulesVersion: Int,
        /** `systemObservation`, `callbackReceipt`, `externalAction` or `personStatement`. */
        val evidenceLevel: String,
        val reasons: List<String>,
    ) {
        val isValid: Boolean
            get() = boundary in BOUNDARIES && source in SOURCES && appliedBy in APPLIED_BY && evidenceLevel in EVIDENCE_LEVELS &&
                timeMs.isFinite() && receivedAtMs.isFinite() && appliedAtMs.isFinite() && (observedAtMs?.isFinite() ?: true) &&
                rulesVersion >= 1 &&
                reasons.size <= MAXIMUM_REASONS &&
                reasons.all { it.isNotEmpty() && SwiftText.characterCount(it) <= MAXIMUM_REASON_LENGTH }
    }

    val isValid: Boolean
        get() = ExtendedScheduleResolver.parse(dayKey) != null &&
            FoundationCompat.isValidTimeZone(timeZoneIdentifier) &&
            boundaries.isNotEmpty() &&
            boundaries.size <= MAXIMUM_BOUNDARIES &&
            boundaries.map { it.boundary }.toSet().size == boundaries.size &&
            boundaries.all { it.isValid } &&
            editCount >= 0

    companion object {
        const val MAXIMUM_BOUNDARIES = 8
        const val MAXIMUM_REASONS = 16
        const val MAXIMUM_REASON_LENGTH = 64
        val BOUNDARIES = setOf("start", "end")
        val SOURCES = setOf("nativeGeofence", "appIntentAutomation", "userConfirmation")
        val APPLIED_BY = setOf("automatic", "reviewed")
        val EVIDENCE_LEVELS = setOf("systemObservation", "callbackReceipt", "externalAction", "personStatement")
    }
}
