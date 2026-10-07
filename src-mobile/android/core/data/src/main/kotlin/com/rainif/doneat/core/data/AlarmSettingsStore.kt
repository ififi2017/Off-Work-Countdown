package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.alarms.ShiftAlarmSettings
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID

/** Caller supplies a path under noBackupFilesDir. These choices never enter the records archive. */
class AlarmSettingsStore(private val file: Path) {
    private val mutex = Mutex()
    private val _settings = MutableStateFlow(read())
    val settings = _settings.asStateFlow()

    suspend fun update(change: (ShiftAlarmSettings) -> ShiftAlarmSettings): Boolean = mutex.withLock {
        val next = change(_settings.value)
        if (next.defaultLeadMinutes !in ShiftAlarmSettings.LEAD_CHOICES ||
            next.leadMinutesByShiftType.values.any { it !in ShiftAlarmSettings.LEAD_CHOICES }) return@withLock false
        if (next == _settings.value) return@withLock true
        try {
            Files.createDirectories(file.parent)
            RecordStore.writeAtomically(file, encode(next).toByteArray())
            _settings.value = next
            true
        } catch (_: Exception) { false }
    }

    private fun read(): ShiftAlarmSettings = runCatching {
        val json = Json.parseToJsonElement(Files.readString(file)).jsonObject
        val lead = json["defaultLeadMinutes"]?.jsonPrimitive?.intOrNull ?: 60
        val perType = (json["leadMinutesByShiftType"] as? JsonObject).orEmpty().mapNotNull { (id, value) ->
            runCatching { UUID.fromString(id) to value.jsonPrimitive.int }.getOrNull()
                ?.takeIf { it.second in ShiftAlarmSettings.LEAD_CHOICES }
        }.toMap()
        val silence = (json["silencedShiftTypeIDs"] as? JsonArray).orEmpty().mapNotNull {
            runCatching { UUID.fromString(it.jsonPrimitive.content) }.getOrNull()
        }.toSet()
        ShiftAlarmSettings(json["enabled"]?.jsonPrimitive?.booleanOrNull ?: false,
            lead.takeIf { it in ShiftAlarmSettings.LEAD_CHOICES } ?: 60, perType, silence)
    }.getOrDefault(ShiftAlarmSettings())

    private fun encode(settings: ShiftAlarmSettings) = buildJsonObject {
        put("enabled", settings.enabled)
        put("defaultLeadMinutes", settings.defaultLeadMinutes)
        put("leadMinutesByShiftType", buildJsonObject {
            settings.leadMinutesByShiftType.toSortedMap(compareBy { it.toString() }).forEach { (id, lead) -> put(id.toString(), lead) }
        })
        put("silencedShiftTypeIDs", JsonArray(settings.silencedShiftTypeIDs.sortedBy { it.toString() }.map { JsonPrimitive(it.toString()) }))
    }.toString()
}
