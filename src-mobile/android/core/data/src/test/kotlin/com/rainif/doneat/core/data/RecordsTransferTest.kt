package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.RecordJson
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.settings.PreferencesRules
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

@OptIn(ExperimentalCoroutinesApi::class)
class RecordsTransferTest {
    @get:Rule val folder = TemporaryFolder()
    private val now = 1_790_000_000_000.0
    private fun archive(name: String) = File(System.getProperty("owc.syntheticArchives"), name).readBytes()

    private suspend fun TestScope.store(): RecordStore =
        RecordStore(folder.root.toPath().resolve("records.json"), { now }, { "Asia/Shanghai" }, UnconfinedTestDispatcher(testScheduler)).also { it.load() }

    @Test fun everyKnownVersionPreviewsAndImports() = runTest {
        for (version in 1..6) {
            val bytes = archive("v$version.json")
            val preview = RecordsTransfer.preview(bytes, RecordState())
            assertTrue("v$version: $preview", preview is ImportPreview.Ready)
            val records = store()
            assertNotNull("v$version commits", RecordsTransfer.commit(records, bytes))
            assertTrue("v$version wrote something", records.state.value != RecordState())
            RecordsTransfer.deleteRecords(records)
        }
    }

    @Test fun aNewerOrBrokenFileIsRefusedWithItsReason() {
        assertSame(ImportPreview.UnsupportedVersion, RecordsTransfer.preview(archive("illegal-v7.json"), RecordState()))
        for (name in listOf("illegal-not-json.txt", "illegal-v0.json")) {
            assertSame(name, ImportPreview.Invalid, RecordsTransfer.preview(archive(name), RecordState()))
        }
        assertSame(ImportPreview.TooLarge, RecordsTransfer.preview(ByteArray((RecordsTransfer.MAX_BYTES + 1).toInt()), RecordState()))
    }

    @Test fun importingTheSameBackupTwiceAddsNothingTheSecondTime() = runTest {
        val records = store()
        val bytes = archive("v6.json")
        RecordsTransfer.commit(records, bytes)
        val once = records.state.value
        val second = RecordsTransfer.preview(bytes, once) as ImportPreview.Ready
        assertEquals(0, second.added)
        assertEquals(0, second.conflicts)
        RecordsTransfer.commit(records, bytes)
        assertEquals(once, records.state.value)
    }

    @Test fun aFailedImportLeavesTheArchiveAsItWas() = runTest {
        val records = store()
        RecordsTransfer.commit(records, archive("v6.json"))
        val before = records.state.value
        assertNull(RecordsTransfer.commit(records, archive("illegal-v7.json")))
        assertEquals(before, records.state.value)
    }

    @Test fun anExportReadsBackAsTheSameRecords() = runTest {
        val records = store()
        RecordsTransfer.commit(records, archive("v6.json"))
        val exported = RecordsTransfer.export(records.state.value, includeLifeProfile = true, now, "Asia/Shanghai")
        val (roundTrip, _) = RecordJson.apply(RecordJson.decode(exported), RecordState(), RecordJson.ImportMode.SKIP_ERASED)
        val original = records.state.value
        assertEquals(original.periods, roundTrip.periods)
        assertEquals(original.snapshots, roundTrip.snapshots)
        assertEquals(original.overrides, roundTrip.overrides)
        assertEquals(original.observations, roundTrip.observations)
        assertEquals(original.lifeProfile, roundTrip.lifeProfile)
    }

    @Test fun theLifeProfileCanBeLeftOut() = runTest {
        val records = store()
        RecordsTransfer.commit(records, archive("v6.json"))
        val withLife = RecordJson.apply(RecordJson.decode(RecordsTransfer.export(records.state.value, true, now, "UTC")), RecordState(), RecordJson.ImportMode.SKIP_ERASED).first
        val withoutLife = RecordJson.apply(RecordJson.decode(RecordsTransfer.export(records.state.value, false, now, "UTC")), RecordState(), RecordJson.ImportMode.SKIP_ERASED).first
        assertNotNull("the fixture carries a Life profile", withLife.lifeProfile)
        assertNull(withoutLife.lifeProfile)
        assertEquals(withLife.periods, withoutLife.periods)
    }

    @Test fun deletingRecordsKeepsTheSettings() = runTest {
        val records = store()
        val prefs = PreferencesRules.defaults("Asia/Shanghai", now)
        records.update { PreferencesRules.commit(it, prefs, now, "00000000-0000-0000-0000-000000000001") to Unit }
        RecordsTransfer.commit(records, archive("v6.json"))
        assertTrue(RecordsTransfer.deleteRecords(records))
        assertTrue(records.state.value.periods.isEmpty())
        assertTrue(records.state.value.observations.isEmpty())
        assertNotNull(records.state.value.syncedPreferences)
    }
}
