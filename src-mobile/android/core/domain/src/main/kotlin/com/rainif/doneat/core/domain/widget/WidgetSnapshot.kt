package com.rainif.doneat.core.domain.widget

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.longOrNull

/**
 * The widget's whole world (the shared `WidgetSnapshotContract`, schema 1):
 * precomputed intervals the widget only picks from by time. It holds no
 * schedule rules and nothing about money: no salary, earnings or records.
 */
const val WIDGET_SNAPSHOT_SCHEMA = 1

enum class WidgetPhase(val key: String) { IDLE("idle"), BEFORE("before"), WORKING("working"), BREAK("break"), DONE("done") }

enum class WidgetCountdownKind(val key: String) {
    NONE("none"), SHIFT_STARTS("shiftStarts"), WORK_REMAINING("workRemaining"), BREAK_ENDS("breakEnds"), COMPLETE("complete"),
}

data class WidgetEntry(
    val dateMs: Long,
    val validUntilMs: Long,
    val phase: WidgetPhase,
    /** A string resource name: "widgetWorking", "lunchInProgress", "offWorkToday"… */
    val labelKey: String,
    val countdownKind: WidgetCountdownKind,
    val countdownValueAtDateMs: Long,
    /** The wall-clock moment counted toward: work start, work resuming, clock-off. */
    val countdownTargetAtMs: Long?,
    val remainingEffectiveMsAtDateMs: Long,
    /** 0…100. */
    val progressAtDate: Double,
    val nextBoundaryAtMs: Long?,
) {
    /**
     * This interval at a later moment inside it (the contract's `projected`,
     * iOS behaviour): working and pre-shift intervals advance linearly; the
     * boundaries themselves always come from the producer.
     */
    fun projected(nowMs: Long): WidgetEntry {
        val advances = phase == WidgetPhase.WORKING || phase == WidgetPhase.BEFORE
        if (!advances || nowMs <= dateMs || progressAtDate >= 100 || remainingEffectiveMsAtDateMs <= 0) return this
        val at = minOf(nowMs, validUntilMs)
        val elapsed = minOf(remainingEffectiveMsAtDateMs, maxOf(0, at - dateMs))
        val remainingFraction = maxOf(0.000_001, 1 - progressAtDate / 100)
        val total = remainingEffectiveMsAtDateMs / remainingFraction
        return copy(
            dateMs = at,
            countdownValueAtDateMs = maxOf(0, countdownValueAtDateMs - elapsed),
            remainingEffectiveMsAtDateMs = maxOf(0, remainingEffectiveMsAtDateMs - elapsed),
            progressAtDate = minOf(100.0, maxOf(progressAtDate, progressAtDate + elapsed / total * 100)),
        )
    }

    /**
     * When the on-screen countdown reaches zero. Remaining effective work,
     * not the wall-clock finish: counting to 19:00 would eat a lunch gap.
     */
    val timerEndAtMs: Long?
        get() = when (countdownKind) {
            WidgetCountdownKind.WORK_REMAINING -> remainingEffectiveMsAtDateMs.takeIf { it > 0 }?.let { dateMs + it }
            else -> countdownTargetAtMs
        }
}

/** One "coming up" row, already worded by the app. */
data class WidgetUpcomingItem(val id: String, val kind: String, val title: String, val detail: String, val dateMs: Long)

data class WidgetSnapshot(
    val schemaVersion: Int,
    val generatedAtMs: Long,
    val expiresAtMs: Long,
    val locale: String,
    val entries: List<WidgetEntry>,
    val upcoming: List<WidgetUpcomingItem> = emptyList(),
) {
    /** The interval covering [nowMs], or null when the snapshot is stale or from another schema. */
    fun entry(nowMs: Long): WidgetEntry? {
        if (schemaVersion != WIDGET_SNAPSHOT_SCHEMA || nowMs < generatedAtMs || nowMs >= expiresAtMs) return null
        return entries.firstOrNull { nowMs >= it.dateMs && nowMs < it.validUntilMs }?.projected(nowMs)
    }

    fun encode(): String = buildJsonObject {
        put("schemaVersion", JsonPrimitive(schemaVersion))
        put("generatedAtMs", JsonPrimitive(generatedAtMs))
        put("expiresAtMs", JsonPrimitive(expiresAtMs))
        put("locale", JsonPrimitive(locale))
        put("entries", JsonArray(entries.map { e ->
            buildJsonObject {
                put("dateMs", JsonPrimitive(e.dateMs))
                put("validUntilMs", JsonPrimitive(e.validUntilMs))
                put("phase", JsonPrimitive(e.phase.key))
                put("labelKey", JsonPrimitive(e.labelKey))
                put("countdownKind", JsonPrimitive(e.countdownKind.key))
                put("countdownValueAtDateMs", JsonPrimitive(e.countdownValueAtDateMs))
                put("countdownTargetAtMs", e.countdownTargetAtMs?.let(::JsonPrimitive) ?: JsonNull)
                put("remainingEffectiveMsAtDateMs", JsonPrimitive(e.remainingEffectiveMsAtDateMs))
                put("progressAtDate", JsonPrimitive(e.progressAtDate))
                put("nextBoundaryAtMs", e.nextBoundaryAtMs?.let(::JsonPrimitive) ?: JsonNull)
            }
        }))
        put("upcoming", JsonArray(upcoming.map { u ->
            buildJsonObject {
                put("id", JsonPrimitive(u.id))
                put("kind", JsonPrimitive(u.kind))
                put("title", JsonPrimitive(u.title))
                put("detail", JsonPrimitive(u.detail))
                put("dateMs", JsonPrimitive(u.dateMs))
            }
        }))
    }.toString()

    companion object {
        /** Null for anything unreadable: the widget then shows its "open the app" state. */
        fun decode(text: String): WidgetSnapshot? = runCatching {
            val o = Json.parseToJsonElement(text).jsonObject
            fun JsonObject.long(key: String) = getValue(key).jsonPrimitive.long
            fun JsonObject.string(key: String) = getValue(key).jsonPrimitive.content
            fun JsonObject.optionalLong(key: String) = (get(key) as? JsonPrimitive)?.longOrNull
            WidgetSnapshot(
                schemaVersion = o.getValue("schemaVersion").jsonPrimitive.int,
                generatedAtMs = o.long("generatedAtMs"),
                expiresAtMs = o.long("expiresAtMs"),
                locale = o.string("locale"),
                entries = o.getValue("entries").jsonArray.map { element ->
                    val e = element.jsonObject
                    WidgetEntry(
                        dateMs = e.long("dateMs"),
                        validUntilMs = e.long("validUntilMs"),
                        phase = WidgetPhase.entries.first { it.key == e.string("phase") },
                        labelKey = e.string("labelKey"),
                        countdownKind = WidgetCountdownKind.entries.first { it.key == e.string("countdownKind") },
                        countdownValueAtDateMs = e.long("countdownValueAtDateMs"),
                        countdownTargetAtMs = e.optionalLong("countdownTargetAtMs"),
                        remainingEffectiveMsAtDateMs = e.long("remainingEffectiveMsAtDateMs"),
                        progressAtDate = e.getValue("progressAtDate").jsonPrimitive.double,
                        nextBoundaryAtMs = e.optionalLong("nextBoundaryAtMs"),
                    )
                },
                upcoming = (o["upcoming"] as? JsonArray).orEmpty().map { element ->
                    val u = element.jsonObject
                    WidgetUpcomingItem(u.string("id"), u.string("kind"), u.string("title"), u.string("detail"), u.long("dateMs"))
                },
            )
        }.getOrNull()
    }
}
