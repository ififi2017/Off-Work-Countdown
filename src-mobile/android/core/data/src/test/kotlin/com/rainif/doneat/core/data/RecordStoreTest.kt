package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.DayOverride
import com.rainif.doneat.core.domain.records.DayOverrideKind
import com.rainif.doneat.core.domain.records.RecordEntityType
import com.rainif.doneat.core.domain.records.RecordJson
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.records.RecordsAccess
import com.rainif.doneat.core.domain.records.RecordsQueries
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.time.LocalDate
import java.time.Instant
import java.time.ZoneId
import java.util.Base64

class RecordStoreTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val now = 1_790_000_000_000.0
    private fun archive(): Path = folder.root.toPath().resolve("records.json")
    private fun store(writer: (Path, ByteArray) -> Unit = RecordStore::writeAtomically) =
        RecordStore(archive(), { now }, { "Asia/Shanghai" }, Dispatchers.Unconfined, writer)

    private fun synthetic(name: String): RecordState {
        val text = File(System.getProperty("owc.syntheticArchives"), name).readText()
        return RecordJson.apply(RecordJson.decode(text), RecordState(), RecordJson.ImportMode.SKIP_ERASED).first
    }

    private fun override(dayKey: String, note: String, segments: List<ShiftSegment> = listOf(ShiftSegment(1.0e12, 1.0e12 + 3_600_000))) =
        DayOverride(dayKey, DayOverrideKind.CUSTOM_SEGMENTS, segments, note, now, 1, "00000000-0000-0000-0000-0000000000AA", "Asia/Shanghai")

    @Test
    fun missingArchiveIsAnEmptyFirstLaunch() = runBlocking {
        val store = store()
        store.load()
        assertEquals(RecordState(), store.state.value)
        assertNull(store.persistenceError.value)
    }

    @Test
    fun everySyntheticArchiveSurvivesARestart() = runBlocking {
        for (name in listOf("v1.json", "v2.json", "v3.json", "v4.json", "v5.json", "v6.json")) {
            Files.deleteIfExists(archive())
            val seeded = synthetic(name)
            val first = store()
            first.load()
            assertTrue(first.update { seeded to Unit } is WriteResult.Saved)
            val reopened = store()
            reopened.load()
            assertEquals(name, seeded, reopened.state.value)
            assertNull(reopened.persistenceError.value)
        }
    }

    @Test
    fun everyOlderLocalEnvelopeWritesBackAsSchemaSix() = runBlocking {
        for (version in 1..6) {
            val document = File(System.getProperty("owc.syntheticArchives"), "v$version.json").readBytes()
            val local = """{"schemaVersion":$version,"document":"${Base64.getEncoder().encodeToString(document)}","erased":[]}"""
            Files.writeString(archive(), local)
            val first = store()
            first.load()
            assertNull("v$version loaded", first.persistenceError.value)
            val before = first.state.value
            assertTrue("v$version wrote", first.update { it.copy(recordsStartedOn = "2026-09-01") to Unit } is WriteResult.Saved)
            val reopened = store()
            reopened.load()
            assertNull("v$version reopened", reopened.persistenceError.value)
            assertEquals("v$version entities", before.copy(recordsStartedOn = "2026-09-01"), reopened.state.value)
            assertTrue("v$version now local schema 6", Files.readString(archive()).contains("\"schemaVersion\":6"))
        }
    }

    @Test
    fun aFailedWriteCommitsNothing() = runBlocking {
        val good = store()
        good.load()
        good.update { it.copy(overrides = listOf(override("2026-09-01", "kept"))) to Unit }
        val before = Files.readAllBytes(archive())

        val failing = store { _, _ -> throw IOException("No space left on device") }
        failing.load()
        val published = failing.state.value
        val result = failing.update { it.copy(overrides = it.overrides + override("2026-09-02", "lost")) to "draft" }
        assertTrue(result is WriteResult.Failed)
        assertEquals(published, failing.state.value)
        assertEquals(RecordPersistenceError.WRITE_FAILED, failing.persistenceError.value)
        assertArrayEquals(before, Files.readAllBytes(archive()))
        assertFalse("write-failed must not block retries", failing.blocksWrites)
    }

    @Test
    fun atomicWriterRemovesPendingFileWhenReplacementFails() {
        val target = folder.root.toPath().resolve("occupied")
        Files.createDirectory(target)
        Files.writeString(target.resolve("keep"), "old")
        val failure = runCatching { RecordStore.writeAtomically(target, "new".toByteArray()) }.exceptionOrNull()
        assertNotNull("a nonempty directory cannot be replaced by an archive", failure)
        assertEquals("old", Files.readString(target.resolve("keep")))
        assertTrue(Files.list(folder.root.toPath()).use { files -> files.noneMatch { it.fileName.toString().endsWith(".pending") } })
    }

    @Test
    fun anEditThatWouldNotReadBackNeverReachesDisk() = runBlocking {
        val store = store()
        store.load()
        store.update { it.copy(overrides = listOf(override("2026-09-01", "kept"))) to Unit }
        val before = Files.readAllBytes(archive())
        // Every shape that would be rejected on read must be rejected before replacement.
        val badSegments = listOf(
            listOf(ShiftSegment(1.0e12, 1.0e12)),
            listOf(ShiftSegment(1.0e12 + 3_600_000, 1.0e12)),
            listOf(ShiftSegment(1.0e12, 1.0e12 + 7_200_000), ShiftSegment(1.0e12 + 3_600_000, 1.0e12 + 9_000_000)),
        )
        for (segments in badSegments) {
            val bad = override("2026-09-03", "bad", segments)
            assertTrue(store.update { it.copy(overrides = it.overrides + bad) to Unit } is WriteResult.Failed)
        }
        assertEquals(1, store.state.value.overrides.size)
        assertArrayEquals(before, Files.readAllBytes(archive()))
    }

    @Test
    fun aPersistedMalformedRowBlocksWritesAndKeepsItsBytes() = runBlocking {
        val seeded = synthetic("v6.json")
        val local = Json.parseToJsonElement(RecordArchive.encode(seeded, now, "Asia/Shanghai").decodeToString()).jsonObject
        val document = Json.parseToJsonElement(Base64.getDecoder().decode(local.getValue("document").jsonPrimitive.content).decodeToString()).jsonObject
        val rows = document.getValue("dayOverrides").jsonArray
        assertEquals("customSegments", rows.first().jsonObject.getValue("kind").jsonPrimitive.content)
        fun segment(start: Long, end: Long) = JsonObject(mapOf("startAtMs" to JsonPrimitive(start), "endAtMs" to JsonPrimitive(end)))
        val invalidFields = listOf(
            "illegal day" to mapOf("dayKey" to JsonPrimitive("2026-99-99")),
            "empty" to mapOf("segments" to JsonArray(emptyList())),
            "zero" to mapOf("segments" to JsonArray(listOf(segment(1_000, 1_000)))),
            "reversed" to mapOf("segments" to JsonArray(listOf(segment(2_000, 1_000)))),
            "overlapping" to mapOf("segments" to JsonArray(listOf(segment(1_000, 3_000), segment(2_000, 4_000)))),
        )
        for ((name, fields) in invalidFields) {
            val brokenDocument = JsonObject(document + ("dayOverrides" to JsonArray(rows.mapIndexed { index, row ->
                if (index == 0) JsonObject(row.jsonObject + fields) else row
            }))).toString().toByteArray()
            val damaged = JsonObject(local + ("document" to JsonPrimitive(Base64.getEncoder().encodeToString(brokenDocument)))).toString().toByteArray()
            Files.write(archive(), damaged)
            val reopened = store()
            reopened.load()
            assertEquals(name, RecordPersistenceError.INVALID_ARCHIVE, reopened.persistenceError.value)
            assertEquals(name, WriteResult.Blocked, reopened.update { it.copy(recordsStartedOn = "2026-09-01") to Unit })
            assertArrayEquals(name, damaged, Files.readAllBytes(archive()))
        }
    }

    @Test
    fun changingDeviceZoneAndReopeningKeepsHistoricalCivilDays() = runBlocking {
        val first = store()
        first.load()
        val seeded = synthetic("v6.json")
        assertTrue(first.update { seeded to Unit } is WriteResult.Saved)
        val reopened = RecordStore(archive(), { now }, { "America/Los_Angeles" }, Dispatchers.Unconfined)
        reopened.load()
        assertEquals(seeded, reopened.state.value)
        val recordsZone = ZoneId.of(reopened.state.value.periods.single().timeZoneIdentifier)
        val queries = RecordsQueries(reopened.state.value, HolidayCalendar.EMPTY, recordsZone, true)
        val key = LocalDate.parse(reopened.state.value.overrides.single().dayKey)
        assertTrue(queries.recordDayIndex.any { it.dayKey == key.toString() })
        assertEquals(key.atStartOfDay(recordsZone).toInstant().toEpochMilli().toDouble(), queries.dayStartMs(key), 0.0)
        val instant = Instant.parse("2026-09-16T01:00:00Z")
        val recordsToday = queries.today(instant.toEpochMilli().toDouble())
        assertEquals(LocalDate.of(2026, 9, 16), recordsToday)
        assertEquals(LocalDate.of(2026, 9, 15), instant.atZone(ZoneId.of("America/Los_Angeles")).toLocalDate())
        assertTrue(RecordsAccess.canRevealDay(recordsToday.minusDays(6), recordsToday, false))
        assertFalse(RecordsAccess.canRevealDay(recordsToday.minusDays(7), recordsToday, false))
    }

    @Test
    fun quarantiningTwiceAtTheSameInstantPreservesBothOriginalFiles() = runBlocking {
        val first = "{first damaged file".toByteArray()
        val second = "{second damaged file".toByteArray()
        Files.write(archive(), first)
        val records = store()
        records.load()
        val a = records.quarantine()!!
        Files.write(archive(), second)
        records.load()
        val b = records.quarantine()!!
        assertTrue(a != b)
        assertTrue(a.fileName.toString().endsWith(".corrupt"))
        assertArrayEquals(first, Files.readAllBytes(a))
        assertArrayEquals(second, Files.readAllBytes(b))
    }

    @Test
    fun aDamagedArchiveBlocksWritesUntilQuarantined() = runBlocking {
        Files.write(archive(), "{\"document\":\"not base64!\"}".toByteArray())
        val damaged = Files.readAllBytes(archive())
        val store = store()
        store.load()
        assertEquals(RecordPersistenceError.INVALID_ARCHIVE, store.persistenceError.value)
        assertEquals(WriteResult.Blocked, store.update { it.copy(recordsStartedOn = "2026-01-01") to Unit })
        assertArrayEquals("a damaged file is never overwritten", damaged, Files.readAllBytes(archive()))

        val moved = store.quarantine()
        assertNotNull(moved)
        assertArrayEquals(damaged, Files.readAllBytes(moved!!))
        assertTrue(store.update { it.copy(recordsStartedOn = "2026-01-01") to Unit } is WriteResult.Saved)
    }

    @Test
    fun aNewerLocalArchiveIsPreservedAndBlocksWrites() = runBlocking {
        val seeded = synthetic("v6.json")
        val current = RecordArchive.encode(seeded, now, "Asia/Shanghai").decodeToString()
        assertTrue(current.contains("\"schemaVersion\":6"))
        val newer = current.replaceFirst("\"schemaVersion\":6", "\"schemaVersion\":7").toByteArray()
        Files.write(archive(), newer)
        val reopened = store()
        reopened.load()
        assertEquals(RecordPersistenceError.INVALID_ARCHIVE, reopened.persistenceError.value)
        assertEquals(WriteResult.Blocked, reopened.update { it.copy(recordsStartedOn = "2026-09-01") to Unit })
        assertArrayEquals(newer, Files.readAllBytes(archive()))
    }

    @Test
    fun tombstonesPersistAndStillBlockImports() = runBlocking {
        val store = store()
        store.load()
        store.update { synthetic("v6.json") to Unit }
        store.update { RecordJson.erase(it, RecordEntityType.DAY_OVERRIDE, "2026-08-24", now) to Unit }
        val reopened = store()
        reopened.load()
        assertEquals(1, reopened.state.value.erased.size)
        val (_, report) = RecordJson.apply(
            RecordJson.decode(File(System.getProperty("owc.syntheticArchives"), "v6.json").readText()),
            reopened.state.value,
            RecordJson.ImportMode.SKIP_ERASED,
        )
        assertEquals(1, report.skippedErased[RecordEntityType.DAY_OVERRIDE])
    }

    @Test
    fun legacyAutomaticPeriodMovesToTheFirstRecordedDay() {
        val seeded = synthetic("v6.json")
        val legacy = seeded.copy(periods = listOf(seeded.periods.single().copy(startsOn = "2000-01-01", label = null)), recordsStartedOn = null)
        val migrated = RecordArchive.migrateLegacyAutomaticPeriod(legacy, now)
        assertEquals("2026-08-24", migrated.periods.single().startsOn)
        assertEquals("2026-08-24", migrated.recordsStartedOn)
    }

    @Test
    fun concurrentWritesAreSerialised() = runBlocking {
        val store = RecordStore(archive(), { now }, { "GMT" }, Dispatchers.IO)
        store.load()
        (1..40).map { day ->
            async(Dispatchers.Default) {
                store.update { it.copy(overrides = it.overrides + override(java.time.LocalDate.of(2026, 1, 1).plusDays(day.toLong()).toString(), "n$day")) to Unit }
            }
        }.awaitAll()
        assertEquals(40, store.state.value.overrides.size)
        val reopened = store()
        reopened.load()
        assertEquals(40, reopened.state.value.overrides.size)
        assertTrue("no pending files left", Files.list(folder.root.toPath()).use { files -> files.noneMatch { it.fileName.toString().endsWith(".pending") } })
    }
}
