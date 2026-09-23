package com.rainif.doneat.core.domain.records

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Holds [RecordJson] to iOS `RecordJSON`'s own answers
 * (`npm run generate:android-record-fixtures`, macOS): document acceptance,
 * per-row rejections, merge reports and the resulting v6 export.
 */
class RecordJsonFixtureTest {
    private val cases: List<JsonObject> by lazy {
        val text = checkNotNull(javaClass.getResource("/record-json-fixtures.json")).readText()
        Json.parseToJsonElement(text).jsonObject.getValue("cases").jsonArray.map { it.jsonObject }
    }

    @Test
    fun everyCaseMatchesSwift() {
        val failures = ArrayList<String>()
        for (case in cases) {
            val name = case.getValue("name").jsonPrimitive.content
            val mismatch = runCatching { check(case) }.getOrElse { "threw $it" } ?: continue
            failures += "$name: $mismatch"
        }
        assertTrue("cases: ${cases.size}", cases.size >= 80)
        assertEquals("mismatches:\n" + failures.joinToString("\n"), 0, failures.size)
    }

    private fun check(case: JsonObject): String? {
        val expected = case.getValue("expected").jsonObject
        if (case["kind"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content == "hours") return checkHours(case, expected)
        var state = RecordState()
        case["base"]?.takeIf { it !is JsonNull }?.let { base ->
            state = RecordJson.apply(RecordJson.decode(base.jsonPrimitive.content), state, RecordJson.ImportMode.SKIP_ERASED).first
        }
        case["erase"]?.takeIf { it !is JsonNull }?.jsonArray?.forEach { pair ->
            val (type, key) = pair.jsonArray.map { it.jsonPrimitive.content }
            state = RecordJson.erase(state, RecordEntityType.fromRaw(type)!!, key, 1_790_000_000_000.0)
        }
        val mode = when (case["mode"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content) {
            "restoreErased" -> RecordJson.ImportMode.RESTORE_ERASED
            "resolveByEditStamp" -> RecordJson.ImportMode.RESOLVE_BY_EDIT_STAMP
            else -> RecordJson.ImportMode.SKIP_ERASED
        }
        val outcome = expected.getValue("outcome").jsonPrimitive.content
        val document = try {
            RecordJson.decode(case.getValue("input").jsonPrimitive.content)
        } catch (e: RecordJson.Error.UnknownSchemaVersion) {
            if (outcome != "unknownSchemaVersion") return "expected $outcome, got unknownSchemaVersion"
            return if (e.version == expected.getValue("schemaVersion").jsonPrimitive.int) null else "version ${e.version}"
        } catch (e: RecordJson.Error.InvalidDocument) {
            return if (outcome == "invalidDocument") null else "expected $outcome, got invalidDocument (${e.message})"
        }
        if (outcome != "ok") return "expected $outcome, but the document decoded"
        val (next, report) = RecordJson.apply(document, state, mode)

        fun counts(map: Map<RecordEntityType, Int>) = map.mapKeys { it.key.raw }
        fun expectedCounts(key: String) = expected.getValue(key).jsonObject.mapValues { it.value.jsonPrimitive.int }
        if (counts(report.inserted) != expectedCounts("inserted")) return "inserted ${counts(report.inserted)} vs ${expectedCounts("inserted")}"
        if (counts(report.unchanged) != expectedCounts("unchanged")) return "unchanged ${counts(report.unchanged)}"
        if (counts(report.skippedErased) != expectedCounts("skippedErased")) return "skippedErased ${counts(report.skippedErased)}"
        if (counts(report.restored) != expectedCounts("restored")) return "restored ${counts(report.restored)}"
        val rejected = report.rejected.map { listOf(it.entityType.raw, it.logicalKey) }
        if (rejected != rows(expected, "rejected")) return "rejected $rejected vs ${rows(expected, "rejected")}"
        val conflicts = report.conflicts.map {
            listOf(it.entityType.raw, it.logicalKey, "${it.localEditCount}", "${it.incomingEditCount}", if (it.appliedIncoming) "applied" else "kept")
        }
        if (conflicts != rows(expected, "conflicts")) return "conflicts $conflicts vs ${rows(expected, "conflicts")}"
        val adopted = report.adopted.map { listOf(it.entityType.raw, it.logicalKey, "${it.editCount}", it.editTieBreaker) }
        if (adopted != rows(expected, "adopted")) return "adopted $adopted vs ${rows(expected, "adopted")}"

        val exported = RecordJson.export(
            next,
            exportedAtMs = document.exportedAtMs,
            timeZoneIdentifier = FoundationCompat.timeZoneIdentifier(document.timeZoneIdentifier) ?: "GMT",
            calendarIdentifier = if (document.calendarIdentifier == "iso8601") "iso8601" else "gregorian",
        )
        val want = canonical(Json.parseToJsonElement(expected.getValue("exportJSON").jsonPrimitive.content))
        val got = canonical(Json.parseToJsonElement(exported))
        return if (want == got) null else "export differs:\n  swift  ${firstDifference(want, got)}"
    }

    /** Snapshot hours must re-encode to Swift's exact bytes, so fingerprints agree across platforms. */
    private fun checkHours(case: JsonObject, expected: JsonObject): String? {
        val decoded = ScheduleHoursCodec.decode(case.getValue("input").jsonPrimitive.content.toByteArray())
        val outcome = expected.getValue("outcome").jsonPrimitive.content
        if (decoded == null) return if (outcome == "invalidHours") null else "expected $outcome, hours did not decode"
        if (outcome != "ok") return "expected $outcome, hours decoded"
        val encoded = ScheduleHoursCodec.encode(decoded)
        val want = expected.getValue("encoded").jsonPrimitive.content
        val got = encoded.data.toString(Charsets.UTF_8)
        if (want != got) return "encoded\n  swift  $want\n  kotlin $got"
        return if (encoded.fingerprint == expected.getValue("fingerprint").jsonPrimitive.content) null else "fingerprint"
    }

    private fun rows(o: JsonObject, key: String) = o.getValue(key).jsonArray.map { row -> row.jsonArray.map { it.jsonPrimitive.content } }

    /** Sorted keys, nulls dropped, numbers compared as doubles. */
    private fun canonical(e: JsonElement): JsonElement = when (e) {
        is JsonObject -> JsonObject(e.filterValues { it !is JsonNull }.mapValues { canonical(it.value) }.toSortedMap())
        is JsonArray -> JsonArray(e.map(::canonical))
        is JsonNull -> e
        is JsonPrimitive -> if (e.isString || e.content == "true" || e.content == "false") e else JsonPrimitive(e.content.toDouble())
    }

    private fun firstDifference(a: JsonElement, b: JsonElement, path: String = "$"): String {
        if (a is JsonObject && b is JsonObject) {
            for (key in (a.keys + b.keys).toSortedSet()) {
                val x = a[key]
                val y = b[key]
                if (x != y) return if (x == null || y == null) "$path.$key: $x vs kotlin $y" else firstDifference(x, y, "$path.$key")
            }
        }
        if (a is JsonArray && b is JsonArray) {
            if (a.size != b.size) return "$path: ${a.size} items vs kotlin ${b.size}"
            for (i in a.indices) if (a[i] != b[i]) return firstDifference(a[i], b[i], "$path[$i]")
        }
        return "$path: $a vs kotlin $b"
    }
}
