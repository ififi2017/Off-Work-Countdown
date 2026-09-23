package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.settings.PreferencesRules
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

@OptIn(ExperimentalCoroutinesApi::class)
class FirstRunRestoreTest {
    @get:Rule val folder = TemporaryFolder()
    private val now = 1_790_000_000_000.0
    private fun archive(name: String) = File(System.getProperty("owc.syntheticArchives"), name).readBytes()

    @Test fun aValidBackupPreviewsWithoutWritingAnything() {
        val preview = FirstRunRestore.preview(archive("v6.json"), now)
        assertTrue(preview is RestorePreview.Ready)
        preview as RestorePreview.Ready
        assertTrue(preview.itemCount > 0)
        assertEquals(FirstRunRestore.itemCount(preview.state), preview.itemCount)
    }

    @Test fun notABackupIsReportedNotThrown() {
        for (name in listOf("illegal-not-json.txt", "illegal-v0.json", "illegal-v7.json")) {
            assertSame(name, RestorePreview.Unreadable, FirstRunRestore.preview(archive(name), now))
        }
        assertSame(RestorePreview.TooLarge, FirstRunRestore.preview(ByteArray((FirstRunRestore.MAX_BYTES + 1).toInt()), now))
    }

    @Test fun restoringWritesTheWholeArchiveOntoAnEmptyDevice() = runTest {
        val store = RecordStore(folder.root.toPath().resolve("records.json"), { now }, { "Asia/Shanghai" }, UnconfinedTestDispatcher(testScheduler))
        store.load()
        val preview = FirstRunRestore.preview(archive("v6.json"), now) as RestorePreview.Ready
        assertTrue(FirstRunRestore.commit(store, preview))
        assertEquals(preview.state, store.state.value)
        // Reopening reads back the same records.
        val reopened = RecordStore(folder.root.toPath().resolve("records.json"), { now }, { "Asia/Shanghai" }, UnconfinedTestDispatcher(testScheduler))
        reopened.load()
        assertEquals(FirstRunRestore.itemCount(preview.state), FirstRunRestore.itemCount(reopened.state.value))
    }

    @Test fun aDeviceThatAlreadyHoldsRecordsIsNeverOverwritten() = runTest {
        val store = RecordStore(folder.root.toPath().resolve("records.json"), { now }, { "Asia/Shanghai" }, UnconfinedTestDispatcher(testScheduler))
        store.load()
        store.update { PreferencesRules.commit(it, PreferencesRules.defaults("Asia/Shanghai", now), now, "00000000-0000-4000-8000-000000000001") to Unit }
        val before = store.state.value
        val preview = FirstRunRestore.preview(archive("v6.json"), now) as RestorePreview.Ready
        assertFalse(FirstRunRestore.commit(store, preview))
        assertEquals(before, store.state.value)
        assertFalse(before == RecordState())
    }
}
