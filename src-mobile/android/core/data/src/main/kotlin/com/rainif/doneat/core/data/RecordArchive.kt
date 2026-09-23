package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.ErasedID
import com.rainif.doneat.core.domain.records.FoundationCompat
import com.rainif.doneat.core.domain.records.RecordEntityType
import com.rainif.doneat.core.domain.records.RecordJson
import com.rainif.doneat.core.domain.records.RecordState
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.double
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.Instant
import java.time.ZoneId

/**
 * The local archive file, in iOS's `RecordLocalFile` shape: the schema-6
 * backup document (base64, exactly what an export would write), plus the
 * tombstones a backup never carries. One codec serves the local file, export
 * and import, which is why Android keeps records in a file rather than tables.
 */
object RecordArchive {
    class InvalidArchive(message: String) : Exception(message)

    /**
     * Encodes [state] and proves it reads back: the document is decoded and
     * applied into an empty archive, and any rejected row fails the write, so
     * a bad edit can never reach disk.
     */
    fun encode(state: RecordState, exportedAtMs: Double, fallbackZone: String): ByteArray {
        val zone = state.periods.firstOrNull()?.timeZoneIdentifier?.let(FoundationCompat::timeZoneIdentifier)
            ?: FoundationCompat.timeZoneIdentifier(fallbackZone) ?: "GMT"
        val document = RecordJson.export(state, exportedAtMs, zone, "gregorian")
        val (_, report) = RecordJson.apply(RecordJson.decode(document), RecordState(), RecordJson.ImportMode.SKIP_ERASED)
        if (report.rejected.isNotEmpty()) throw InvalidArchive("rows would not read back: ${report.rejected}")
        val file = JsonObject(
            mapOf(
                "schemaVersion" to JsonPrimitive(RecordJson.SCHEMA_VERSION),
                "document" to JsonPrimitive(FoundationCompat.base64(document.toByteArray(Charsets.UTF_8))),
                "erased" to JsonArray(state.erased.map {
                    JsonObject(
                        mapOf(
                            "entityType" to JsonPrimitive(it.entityType.raw),
                            "logicalKey" to JsonPrimitive(it.logicalKey),
                            "erasedAtMs" to JsonPrimitive(it.erasedAtMs),
                            "editCount" to JsonPrimitive(it.editCount),
                        ),
                    )
                }),
            ),
        )
        return Json.encodeToString(JsonObject.serializer(), file).toByteArray(Charsets.UTF_8)
    }

    /** Reads a local file. Anything that does not decode cleanly is invalid, never an empty archive. */
    fun decode(bytes: ByteArray, nowMs: Double): RecordState {
        val file = try {
            Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject
        } catch (e: Exception) {
            throw InvalidArchive("not a local archive")
        }
        return try {
            val documentBytes = FoundationCompat.base64(file.getValue("document").jsonPrimitive.content)
                ?: throw InvalidArchive("document is not base64")
            val (state, report) = RecordJson.apply(
                RecordJson.decode(documentBytes.toString(Charsets.UTF_8)), RecordState(), RecordJson.ImportMode.SKIP_ERASED,
            )
            if (report.rejected.isNotEmpty()) throw InvalidArchive("rejected rows: ${report.rejected}")
            val erased = file["erased"]?.jsonArray.orEmpty().map { e ->
                val o = e.jsonObject
                ErasedID(
                    entityType = RecordEntityType.fromRaw(o.getValue("entityType").jsonPrimitive.content) ?: throw InvalidArchive("entity type"),
                    logicalKey = o.getValue("logicalKey").jsonPrimitive.content,
                    erasedAtMs = o.getValue("erasedAtMs").jsonPrimitive.double,
                    // Optional so tombstones written before versioning still decode.
                    editCount = o["editCount"]?.jsonPrimitive?.intOrNull ?: 0,
                )
            }
            migrateLegacyAutomaticPeriod(state.copy(erased = erased), nowMs)
        } catch (e: InvalidArchive) {
            throw e
        } catch (e: Exception) {
            throw InvalidArchive(e.message ?: "malformed archive")
        }
    }

    /**
     * Early builds created one unlabeled period starting 2000-01-01. It moves
     * to the earliest recorded day (or today) and seeds `recordsStartedOn`.
     */
    internal fun migrateLegacyAutomaticPeriod(state: RecordState, nowMs: Double): RecordState {
        val period = state.periods.singleOrNull() ?: return state
        if (period.label != null || period.startsOn != "2000-01-01") return state
        val today = FoundationCompat.dayKey(Instant.ofEpochMilli(nowMs.toLong()).atZone(javaZone(period.timeZoneIdentifier)).toLocalDate())
        val earliest = (state.observations.map { it.shiftAnchorDate } + state.overrides.map { it.dayKey } + state.exceptions.map { it.date } + today).min()
        return state.copy(
            periods = listOf(period.copy(startsOn = earliest)),
            recordsStartedOn = state.recordsStartedOn ?: earliest,
        )
    }

    /** A Foundation identifier as a `java.time` zone; abbreviations resolve like Foundation's dictionary. */
    fun javaZone(identifier: String): ZoneId =
        runCatching { ZoneId.of(identifier, ZoneId.SHORT_IDS) }.getOrElse { ZoneId.of("GMT") }
}
