package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.DayOverride
import com.rainif.doneat.core.domain.records.DayOverrideKind
import com.rainif.doneat.core.domain.records.RecordEntityType
import com.rainif.doneat.core.domain.records.RecordJson
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.schedule.ShiftSegment
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
    fun anEditThatWouldNotReadBackNeverReachesDisk() = runBlocking {
        val store = store()
        store.load()
        store.update { it.copy(overrides = listOf(override("2026-09-01", "kept"))) to Unit }
        val before = Files.readAllBytes(archive())
        // Overlapping custom segments are rejected on read, so they must be rejected on write.
        val bad = override("2026-09-03", "bad", listOf(ShiftSegment(1.0e12, 1.0e12 + 7_200_000), ShiftSegment(1.0e12 + 3_600_000, 1.0e12 + 9_000_000)))
        assertTrue(store.update { it.copy(overrides = it.overrides + bad) to Unit } is WriteResult.Failed)
        assertEquals(1, store.state.value.overrides.size)
        assertArrayEquals(before, Files.readAllBytes(archive()))
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
