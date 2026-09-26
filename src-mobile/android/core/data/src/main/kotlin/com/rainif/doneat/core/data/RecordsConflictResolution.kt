package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.ImportConflictCopy
import com.rainif.doneat.core.domain.records.RecordEntityType
import com.rainif.doneat.core.domain.records.RecordJson
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.records.SyncedPreferences
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive


/** A file import parks unresolved copies; either explicit choice is one durable archive edit. */
object RecordsConflictResolution {
    enum class Choice { KEEP_CURRENT, USE_IMPORTED }

    data class Field(val name: String, val current: JsonElement?, val incoming: JsonElement?)
    data class Review(val current: Any, val title: String?, val fields: List<Field>, val canUseIncoming: Boolean)

    /** Values come from the same codec that import uses, so both sides are reviewed as stored. */
    fun review(state: RecordState, conflict: ImportConflictCopy): Review? = runCatching {
        val current = currentRow(state, conflict) ?: return@runCatching null
        val document = RecordJson.decode(conflict.incomingDocument)
        val localDoc = RecordJson.export(RecordsTransfer.singleRow(current), document.exportedAtMs, document.timeZoneIdentifier, document.calendarIdentifier)
        val local = row(Json.parseToJsonElement(localDoc).jsonObject, conflict.entityType)
        val incoming = row(Json.parseToJsonElement(conflict.incomingDocument).jsonObject, conflict.entityType)
        val hidden = setOf("id", "profileID", "eventID", "dayKey", "periodID", "scheduleSnapshotID", "editCount", "editTieBreaker", "editedAtMs", "createdAtMs")
        val fields = (local.keys + incoming.keys).toSortedSet().filterNot { it in hidden }.mapNotNull { name ->
            val a = local[name]
            val b = incoming[name]
            if (a == b) null else Field(name, a, b)
        }
        val title = when (conflict.entityType) {
            RecordEntityType.CAREER_PERIOD -> local["label"]?.toString()?.trim('"') ?: local["startsOn"]?.toString()?.trim('"')
            RecordEntityType.FOCUS_TASK -> local["title"]?.toString()?.trim('"')
            else -> local["date"]?.toString()?.trim('"') ?: local["shiftAnchorDate"]?.toString()?.trim('"')
                ?: local["effectiveFrom"]?.toString()?.trim('"') ?: local["dayKey"]?.toString()?.trim('"')
        }
        val canUseIncoming = conflict.entityType != RecordEntityType.SYNCED_PREFERENCES ||
            incoming["recordsTimeZoneIdentifier"]?.jsonPrimitive?.content == (current as SyncedPreferences).recordsTimeZoneIdentifier
        Review(current, title, fields, canUseIncoming)
    }.getOrNull()

    suspend fun resolve(records: RecordStore, conflict: ImportConflictCopy, expectedCurrent: Any, choice: Choice, nowMs: Double, newId: () -> String): Boolean {
        var resolved = false
        val result = records.update { current ->
            val pending = current.importConflicts.firstOrNull { it.entityType == conflict.entityType && it.logicalKey == conflict.logicalKey }
                ?: return@update current to Unit
            if (pending.id != conflict.id || currentRow(current, pending) != expectedCurrent) return@update current to Unit
            if (current.isErased(pending.entityType, pending.logicalKey)) return@update current to Unit
            val chosen = if (choice == Choice.USE_IMPORTED) {
                val (applied, report) = try {
                    RecordJson.apply(RecordJson.decode(pending.incomingDocument), current, RecordJson.ImportMode.FORCE_INCOMING)
                } catch (_: Exception) { return@update current to Unit }
                if (report.rejected.isNotEmpty()) return@update current to Unit
                if (pending.entityType == RecordEntityType.SYNCED_PREFERENCES &&
                    applied.syncedPreferences?.recordsTimeZoneIdentifier != current.syncedPreferences?.recordsTimeZoneIdentifier) return@update current to Unit
                applied
            } else current
            val previousCount = maxOf(pending.localEditCount, pending.incomingEditCount, editCount(expectedCurrent))
            if (previousCount == Int.MAX_VALUE) return@update current to Unit
            val stamped = stamp(chosen, pending, previousCount + 1, nowMs, newId())
                ?: return@update current to Unit
            resolved = true
            stamped.copy(importConflicts = stamped.importConflicts.filterNot {
                it.entityType == pending.entityType && it.logicalKey == pending.logicalKey
            }) to Unit
        }
        return resolved && result is WriteResult.Saved
    }

    private fun row(document: JsonObject, type: RecordEntityType): JsonObject {
        val name = when (type) {
            RecordEntityType.CAREER_PERIOD -> "careerPeriods"
            RecordEntityType.SCHEDULE_SNAPSHOT -> "scheduleSnapshots"
            RecordEntityType.CALENDAR_EXCEPTION -> "calendarExceptions"
            RecordEntityType.DAY_OVERRIDE -> "dayOverrides"
            RecordEntityType.WORK_OBSERVATION -> "workObservations"
            RecordEntityType.LIFE_PROFILE -> "lifeProfile"
            RecordEntityType.FOCUS_TASK -> "focusTasks"
            RecordEntityType.FOCUS_SESSION -> "focusSessions"
            RecordEntityType.FOCUS_PLANNING_CONFIGURATION -> "focusPlanningConfiguration"
            RecordEntityType.SYNCED_PREFERENCES -> "syncedPreferences"
            RecordEntityType.EXTENDED_SCHEDULE -> "extendedSchedule"
            RecordEntityType.ROSTER_DAY -> "rosterDays"
        }
        val value = document.getValue(name)
        return (if (value is JsonArray) value.single() else value).jsonObject
    }

    private fun currentRow(s: RecordState, c: ImportConflictCopy): Any? = when (c.entityType) {
        RecordEntityType.CAREER_PERIOD -> s.periods.firstOrNull { it.id == c.logicalKey }
        RecordEntityType.SCHEDULE_SNAPSHOT -> s.snapshots.firstOrNull { it.id == c.logicalKey }
        RecordEntityType.CALENDAR_EXCEPTION -> s.exceptions.firstOrNull { it.dayKey == c.logicalKey }
        RecordEntityType.DAY_OVERRIDE -> s.overrides.firstOrNull { it.dayKey == c.logicalKey }
        RecordEntityType.WORK_OBSERVATION -> s.observations.firstOrNull { it.eventID == c.logicalKey }
        RecordEntityType.LIFE_PROFILE -> s.lifeProfile
        RecordEntityType.FOCUS_TASK -> s.focusTasks.firstOrNull { it.id == c.logicalKey }
        RecordEntityType.FOCUS_SESSION -> s.focusSessions.firstOrNull { it.id == c.logicalKey }
        RecordEntityType.FOCUS_PLANNING_CONFIGURATION -> s.focusPlanningConfiguration
        RecordEntityType.SYNCED_PREFERENCES -> s.syncedPreferences
        RecordEntityType.EXTENDED_SCHEDULE -> s.extendedSchedule
        RecordEntityType.ROSTER_DAY -> s.rosterDays.firstOrNull { it.dayKey == c.logicalKey }
    }

    private fun editCount(row: Any): Int = when (row) {
        is com.rainif.doneat.core.domain.records.CareerPeriod -> row.editCount
        is com.rainif.doneat.core.domain.records.ScheduleSnapshot -> row.editCount
        is com.rainif.doneat.core.domain.records.CalendarException -> row.editCount
        is com.rainif.doneat.core.domain.records.DayOverride -> row.editCount
        is com.rainif.doneat.core.domain.records.WorkObservation -> row.editCount
        is com.rainif.doneat.core.domain.records.LifeProfile -> row.editCount
        is com.rainif.doneat.core.domain.records.FocusTask -> row.editCount
        is com.rainif.doneat.core.domain.records.FocusSession -> row.editCount
        is com.rainif.doneat.core.domain.records.FocusPlanningConfiguration -> row.editCount
        is com.rainif.doneat.core.domain.records.SyncedPreferences -> row.editCount
        is com.rainif.doneat.core.domain.schedule.ExtendedSchedule -> row.editCount
        is com.rainif.doneat.core.domain.schedule.RosterDay -> row.editCount
        else -> error("unknown conflict row")
    }

    private fun stamp(s: RecordState, c: ImportConflictCopy, count: Int, now: Double, tie: String): RecordState? {
        val key = c.logicalKey
        return when (c.entityType) {
            RecordEntityType.CAREER_PERIOD -> s.periods.indexOfFirst { it.id == key }.takeIf { it >= 0 }?.let { i -> s.copy(periods = s.periods.toMutableList().also { it[i] = it[i].copy(editCount = count, editedAtMs = now, editTieBreaker = tie) }) }
            RecordEntityType.SCHEDULE_SNAPSHOT -> s.snapshots.indexOfFirst { it.id == key }.takeIf { it >= 0 }?.let { i -> s.copy(snapshots = s.snapshots.toMutableList().also { it[i] = it[i].copy(editCount = count, editedAtMs = now, editTieBreaker = tie) }) }
            RecordEntityType.CALENDAR_EXCEPTION -> s.exceptions.indexOfFirst { it.dayKey == key }.takeIf { it >= 0 }?.let { i -> s.copy(exceptions = s.exceptions.toMutableList().also { it[i] = it[i].copy(editCount = count, editedAtMs = now, editTieBreaker = tie) }) }
            RecordEntityType.DAY_OVERRIDE -> s.overrides.indexOfFirst { it.dayKey == key }.takeIf { it >= 0 }?.let { i -> s.copy(overrides = s.overrides.toMutableList().also { it[i] = it[i].copy(editCount = count, editedAtMs = now, editTieBreaker = tie) }) }
            RecordEntityType.WORK_OBSERVATION -> s.observations.indexOfFirst { it.eventID == key }.takeIf { it >= 0 }?.let { i -> s.copy(observations = s.observations.toMutableList().also { it[i] = it[i].copy(editCount = count, editedAtMs = now, editTieBreaker = tie) }) }
            RecordEntityType.LIFE_PROFILE -> s.lifeProfile?.let { s.copy(lifeProfile = it.copy(editCount = count, editedAtMs = now, editTieBreaker = tie)) }
            RecordEntityType.FOCUS_TASK -> s.focusTasks.indexOfFirst { it.id == key }.takeIf { it >= 0 }?.let { i -> s.copy(focusTasks = s.focusTasks.toMutableList().also { it[i] = it[i].copy(editCount = count, editedAtMs = now, editTieBreaker = tie) }) }
            RecordEntityType.FOCUS_SESSION -> s.focusSessions.indexOfFirst { it.id == key }.takeIf { it >= 0 }?.let { i -> s.copy(focusSessions = s.focusSessions.toMutableList().also { it[i] = it[i].copy(editCount = count, editedAtMs = now, editTieBreaker = tie) }) }
            RecordEntityType.FOCUS_PLANNING_CONFIGURATION -> s.focusPlanningConfiguration?.let { s.copy(focusPlanningConfiguration = it.copy(editCount = count, editedAtMs = now, editTieBreaker = tie)) }
            RecordEntityType.SYNCED_PREFERENCES -> s.syncedPreferences?.let { s.copy(syncedPreferences = it.copy(editCount = count, editedAtMs = now, editTieBreaker = tie)) }
            RecordEntityType.EXTENDED_SCHEDULE -> s.extendedSchedule?.let { s.copy(extendedSchedule = it.copy(editCount = count, editedAtMs = now, editTieBreaker = tie)) }
            RecordEntityType.ROSTER_DAY -> s.rosterDays.indexOfFirst { it.dayKey == key }.takeIf { it >= 0 }?.let { i -> s.copy(rosterDays = s.rosterDays.toMutableList().also { it[i] = it[i].copy(editCount = count, editedAtMs = now, editTieBreaker = tie) }) }
        }
    }
}
