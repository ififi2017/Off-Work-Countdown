package com.rainif.doneat.core.domain.records

import com.rainif.doneat.core.domain.schedule.ExtendedScheduleContent
import com.rainif.doneat.core.domain.schedule.ScheduleHours
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ShiftCycleRule
import com.rainif.doneat.core.domain.schedule.WorkSchedule
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.security.MessageDigest
import java.util.Locale

/**
 * The hours a schedule snapshot stores (iOS `ScheduleHoursConfiguration`).
 * Salary, overtime and "now" stay out, and so do hand-set roster days: the
 * extended schedule's types and rule travel as [extendedContent], and the live
 * plan is attached only at read time ([RecordHistory.expandableHours]).
 *
 * [modeRaw] keeps the stored mode text so a snapshot round-trips even when a
 * newer build wrote a mode this one does not know.
 */
data class SnapshotHours(
    val startTime: String,
    val endTime: String,
    val workdays: List<Int>,
    val modeRaw: String,
    val referenceWeekStartMs: Double? = null,
    val referenceWeekType: String? = null,
    val singleWeekendWorkday: Int? = null,
    val rotationAnchorMs: Double? = null,
    val rotationWorkDays: Int? = null,
    val rotationRestDays: Int? = null,
    val breakStartTime: String?,
    val breakDurationMinutes: Int,
    val extendedContent: ExtendedScheduleContent? = null,
) {
    /** The rules' view, or null for a mode the rules cannot run. */
    fun scheduleHours(): ScheduleHours? {
        val mode = ScheduleMode.fromRaw(modeRaw) ?: return null
        return ScheduleHours(
            startTime, endTime, workdays,
            WorkSchedule(mode, referenceWeekStartMs, referenceWeekType, singleWeekendWorkday, rotationAnchorMs, rotationWorkDays, rotationRestDays),
            breakStartTime, breakDurationMinutes,
        )
    }

    companion object {
        fun of(hours: ScheduleHours, extendedContent: ExtendedScheduleContent? = null) = SnapshotHours(
            hours.startTime, hours.endTime, hours.workdays, hours.schedule.mode.raw,
            hours.schedule.referenceWeekStartMs, hours.schedule.referenceWeekType, hours.schedule.singleWeekendWorkday,
            hours.schedule.rotationAnchorMs, hours.schedule.rotationWorkDays, hours.schedule.rotationRestDays,
            hours.breakStartTime, hours.breakDurationMinutes, extendedContent,
        )
    }
}

/**
 * Snapshot bytes exactly as iOS `ScheduleHoursCodec` writes them —
 * `JSONEncoder` with sorted keys — so the SHA-256 fingerprint of unchanged
 * hours is the same on both platforms. Held by `record-json-fixtures.json`.
 */
object ScheduleHoursCodec {
    data class Encoded(val data: ByteArray, val fingerprint: String) {
        val base64: String get() = FoundationCompat.base64(data)
    }

    fun encode(hours: SnapshotHours): Encoded {
        val data = write(json(hours)).toByteArray(Charsets.UTF_8)
        val digest = MessageDigest.getInstance("SHA-256").digest(data)
        return Encoded(data, digest.joinToString("") { "%02x".format(Locale.ROOT, it) })
    }

    /** Null when the bytes are not a complete configuration, as `try? JSONDecoder()` is. */
    fun decode(data: ByteArray): SnapshotHours? = runCatching {
        val o = Json.parseToJsonElement(data.toString(Charsets.UTF_8)).jsonObject
        val schedule = o.getValue("schedule").jsonObject
        SnapshotHours(
            startTime = o.req("startTime").string(),
            endTime = o.req("endTime").string(),
            workdays = o.req("workdays").jsonArray.map { it.integer() },
            modeRaw = schedule.req("mode").string(),
            referenceWeekStartMs = schedule.opt("referenceWeekStartMs")?.number(),
            referenceWeekType = schedule.opt("referenceWeekType")?.string(),
            singleWeekendWorkday = schedule.opt("singleWeekendWorkday")?.integer(),
            rotationAnchorMs = schedule.opt("rotationAnchorMs")?.number(),
            rotationWorkDays = schedule.opt("rotationWorkDays")?.integer(),
            rotationRestDays = schedule.opt("rotationRestDays")?.integer(),
            breakStartTime = o.opt("breakStartTime")?.string(),
            breakDurationMinutes = o.req("breakDurationMinutes").integer(),
            extendedContent = o.opt("extendedContent")?.jsonObject?.let { c ->
                ExtendedScheduleContent(
                    shiftTypes = c.req("shiftTypes").jsonArray.map { RecordJson.shiftType(it.jsonObject) },
                    rule = c.opt("rule")?.jsonObject?.let { r ->
                        ShiftCycleRule(
                            ShiftCycleRule.Preset.fromRaw(r.req("preset").string()),
                            r.req("anchorDayKey").string(),
                            r.req("days").jsonArray.map { java.util.UUID.fromString(FoundationCompat.uuid(it.string()) ?: error("uuid")) },
                        )
                    },
                    holidayRegionIdentifier = c.opt("holidayRegionIdentifier")?.string(),
                    clearedFromDayKey = c.opt("clearedFromDayKey")?.string(),
                )
            },
        )
    }.getOrNull()

    fun decodeBase64(configurationData: String): SnapshotHours? = FoundationCompat.base64(configurationData)?.let(::decode)

    private fun json(h: SnapshotHours): JsonObject = obj(
        "startTime" to JsonPrimitive(h.startTime),
        "endTime" to JsonPrimitive(h.endTime),
        "workdays" to JsonArray(h.workdays.map(::JsonPrimitive)),
        "schedule" to obj(
            "mode" to JsonPrimitive(h.modeRaw),
            "referenceWeekStartMs" to h.referenceWeekStartMs?.let(::JsonPrimitive),
            "referenceWeekType" to h.referenceWeekType?.let(::JsonPrimitive),
            "singleWeekendWorkday" to h.singleWeekendWorkday?.let(::JsonPrimitive),
            "rotationAnchorMs" to h.rotationAnchorMs?.let(::JsonPrimitive),
            "rotationWorkDays" to h.rotationWorkDays?.let(::JsonPrimitive),
            "rotationRestDays" to h.rotationRestDays?.let(::JsonPrimitive),
        ),
        "breakStartTime" to h.breakStartTime?.let(::JsonPrimitive),
        "breakDurationMinutes" to JsonPrimitive(h.breakDurationMinutes),
        "extendedContent" to h.extendedContent?.let { c ->
            obj(
                "shiftTypes" to JsonArray(c.shiftTypes.map(RecordJson::shiftTypeJson)),
                "rule" to c.rule?.let { r ->
                    obj(
                        "preset" to JsonPrimitive(r.preset.raw),
                        "anchorDayKey" to JsonPrimitive(r.anchorDayKey),
                        "days" to JsonArray(r.days.map { JsonPrimitive(it.toString().uppercase(Locale.ROOT)) }),
                    )
                },
                "holidayRegionIdentifier" to c.holidayRegionIdentifier?.let(::JsonPrimitive),
                "clearedFromDayKey" to c.clearedFromDayKey?.let(::JsonPrimitive),
            )
        },
    )

    private fun obj(vararg pairs: Pair<String, JsonElement?>) = JsonObject(pairs.mapNotNull { (k, v) -> v?.let { k to it } }.toMap())

    /** `JSONEncoder` with `.sortedKeys`: compact, `/` escaped, non-ASCII raw, integral doubles without `.0`. */
    private fun write(e: JsonElement): String = when (e) {
        is JsonObject -> e.entries.sortedBy { it.key }.joinToString(",", "{", "}") { "${quote(it.key)}:${write(it.value)}" }
        is JsonArray -> e.joinToString(",", "[", "]") { write(it) }
        is JsonNull -> "null"
        is JsonPrimitive -> when {
            e.isString -> quote(e.content)
            e.content == "true" || e.content == "false" -> e.content
            else -> number(e.content.toDouble())
        }
    }

    /**
     * Swift's shortest round-trip digits, written in plain decimal notation as
     * `JSONEncoder` does for the magnitudes schedules use (instants in
     * milliseconds, counts). Kotlin's `toString` would switch to `1.7E12`.
     */
    private fun number(value: Double): String {
        if (value == Math.rint(value) && kotlin.math.abs(value) < 9.007199254740992E15) return value.toLong().toString()
        return java.math.BigDecimal(value.toString()).toPlainString()
    }

    private fun quote(text: String) = buildString {
        append('"')
        for (c in text) {
            when (c) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '/' -> append("\\/")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                '\b' -> append("\\b")
                '\u000C' -> append("\\f")
                else -> if (c < ' ') append("\\u%04x".format(Locale.ROOT, c.code)) else append(c)
            }
        }
        append('"')
    }

    private fun JsonObject.req(key: String) = get(key)?.takeIf { it !is JsonNull } ?: error("missing $key")
    private fun JsonObject.opt(key: String) = get(key)?.takeIf { it !is JsonNull }
    private fun JsonElement.string() = jsonPrimitive.takeIf { it.isString }?.content ?: error("string")
    private fun JsonElement.number() = jsonPrimitive.takeIf { !it.isString }?.content?.toDouble() ?: error("number")
    private fun JsonElement.integer(): Int = number().let { if (it == Math.rint(it)) it.toInt() else error("integer") }
}
