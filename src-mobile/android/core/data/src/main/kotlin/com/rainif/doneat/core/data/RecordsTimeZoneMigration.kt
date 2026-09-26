package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.ErasedID
import com.rainif.doneat.core.domain.records.FoundationCompat
import com.rainif.doneat.core.domain.records.RecordEntityType
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.records.ScheduleHoursCodec
import com.rainif.doneat.core.domain.settings.PreferencesRules
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

/** iOS `RecordCoordinator.migrateCalendarTimeZone`, applied with preferences in one archive write. */
object RecordsTimeZoneMigration {
    fun migrate(state: RecordState, target: String, nowMs: Double, newId: () -> String): RecordState? {
        if (!FoundationCompat.isValidTimeZone(target) || !nowMs.isFinite()) return null
        val preferences = state.syncedPreferences ?: return null
        if (preferences.recordsTimeZoneIdentifier == target) return null
        if (state.periods.any { it.editCount == Int.MAX_VALUE } ||
            state.snapshots.any { it.editCount == Int.MAX_VALUE } ||
            state.overrides.any { it.editCount == Int.MAX_VALUE } ||
            state.exceptions.any { it.editCount == Int.MAX_VALUE } ||
            state.lifeProfile?.editCount == Int.MAX_VALUE ||
            preferences.editCount == Int.MAX_VALUE) return null
        return try {
            val oldPeriods = state.periods.associateBy { it.id }
            val periods = state.periods.map {
                it.copy(timeZoneIdentifier = target, editedAtMs = nowMs, editCount = it.editCount + 1, editTieBreaker = newId())
            }
            val snapshots = state.snapshots.map { snapshot ->
                val old = oldPeriods[snapshot.periodID]
                val hours = ScheduleHoursCodec.decodeBase64(snapshot.configurationData)
                val migrated = if (old != null && hours != null) {
                    ScheduleHoursCodec.encode(hours.copy(
                        referenceWeekStartMs = hours.referenceWeekStartMs?.let { civilAnchor(it, old.timeZoneIdentifier, target) },
                        rotationAnchorMs = hours.rotationAnchorMs?.let { civilAnchor(it, old.timeZoneIdentifier, target) },
                    ))
                } else null
                snapshot.copy(
                    configurationData = migrated?.base64 ?: snapshot.configurationData,
                    fingerprint = migrated?.fingerprint ?: snapshot.fingerprint,
                    editedAtMs = nowMs, editCount = snapshot.editCount + 1, editTieBreaker = newId(),
                )
            }
            val observations = state.observations.map { observation ->
                if (observation.timeZoneIdentifier == target) observation else {
                    val id = migratedObservationId(observation.eventID, target)
                    observation.copy(eventID = id, timeZoneIdentifier = target, editedAtMs = nowMs, editCount = 1, editTieBreaker = id)
                }
            }
            val erased = state.erased + state.observations.filter { it.timeZoneIdentifier != target }.map {
                ErasedID(RecordEntityType.WORK_OBSERVATION, it.eventID, nowMs, it.editCount)
            }
            val updatedPreferences = PreferencesRules.commit(state, preferences.copy(recordsTimeZoneIdentifier = target), nowMs, newId()).syncedPreferences
            state.copy(
                periods = periods, snapshots = snapshots,
                overrides = state.overrides.map { it.copy(timeZoneIdentifier = target, editedAtMs = nowMs, editCount = it.editCount + 1, editTieBreaker = newId()) },
                exceptions = state.exceptions.map { it.copy(timeZoneIdentifier = target, editedAtMs = nowMs, editCount = it.editCount + 1, editTieBreaker = newId()) },
                observations = observations, erased = erased,
                lifeProfile = state.lifeProfile?.let { it.copy(editedAtMs = nowMs, editCount = it.editCount + 1, editTieBreaker = newId()) },
                syncedPreferences = updatedPreferences,
            )
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun civilAnchor(ms: Double, source: String, target: String): Double {
        val date = Instant.ofEpochMilli(ms.toLong()).atZone(ZoneId.of(source)).toLocalDate()
        return date.atStartOfDay(ZoneId.of(target)).toInstant().toEpochMilli().toDouble()
    }

    internal fun migratedObservationId(id: String, zone: String): String {
        val input = "owc.observation.time-zone-migration.v1|${id.lowercase(Locale.ROOT)}|$zone"
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray()).copyOf(16)
        bytes[6] = ((bytes[6].toInt() and 0x0f) or 0x50).toByte()
        bytes[8] = ((bytes[8].toInt() and 0x3f) or 0x80).toByte()
        val hex = bytes.joinToString("") { "%02x".format(Locale.ROOT, it) }
        return UUID.fromString("${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}")
            .toString().uppercase(Locale.ROOT)
    }
}
