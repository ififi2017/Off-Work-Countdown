package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.settings.PreferencesRules
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.nio.file.Files

@OptIn(ExperimentalCoroutinesApi::class)
class SettingsRepositoryTest {
    @get:Rule val folder = TemporaryFolder()
    private val zone = "Asia/Shanghai"
    private var now = 1_790_000_000_000.0
    private var ids = 0
    private val archive by lazy { folder.root.toPath().resolve("records/archive.json") }
    private val deviceFile by lazy { folder.root.toPath().resolve("device/settings.json") }

    private fun TestScope.open(): Triple<RecordStore, DeviceSettingsStore, SettingsRepository> {
        val dispatcher = UnconfinedTestDispatcher(testScheduler)
        val records = RecordStore(archive, { now }, { zone }, dispatcher)
        val device = DeviceSettingsStore(deviceFile)
        val scope = CoroutineScope(backgroundScope.coroutineContext + dispatcher)
        val repo = SettingsRepository(records, device, scope, { now }, { zone }, { "00000000-0000-4000-8000-%012d".format(++ids) })
        return Triple(records, device, repo)
    }

    @Test fun beforeSetupEditsStayInTheDraftAndNeverReachTheArchive() = runTest {
        val (records, _, repo) = open()
        records.load()
        assertFalse(repo.isSetUp.value)
        assertEquals(PreferencesRules.defaults(zone, now).startMinutes, repo.preferences.value.startMinutes)
        assertTrue(repo.edit { it.copy(startMinutes = 8 * 60) })
        assertEquals(480, repo.preferences.value.startMinutes)
        assertNull("no archive row before setup completes", records.state.value.syncedPreferences)
        assertFalse(Files.exists(archive))
        assertFalse("an edit that changes nothing is dropped", repo.edit { it.copy(startMinutes = 8 * 60) })
    }

    @Test fun theDraftSurvivesTheProcessDyingMidSetup() = runTest {
        run {
            val (records, _, repo) = open()
            records.load()
            repo.edit { it.copy(startMinutes = 10 * 60, workdays = listOf(1, 2, 3)) }
            repo.updateDevice { it.copy(setupPage = "REMINDERS") }
        }
        val (records, _, repo) = open()
        records.load()
        assertEquals(600, repo.preferences.value.startMinutes)
        assertEquals(listOf(1, 2, 3), repo.preferences.value.workdays)
        assertEquals("REMINDERS", repo.device.value.setupPage)
    }

    @Test fun completingSetupCommitsTheDraftOnceAndLaterEditsAreStamped() = runTest {
        val (records, device, repo) = open()
        records.load()
        repo.edit { it.copy(theme = "dark") }
        assertTrue(repo.completeSetup())
        val row = records.state.value.syncedPreferences!!
        assertEquals("dark", row.theme)
        assertEquals(1, row.editCount)
        assertTrue(repo.isSetUp.value)
        assertNull(device.settings.value.setupDraft)
        assertNull("setup finished: nothing to resume", device.settings.value.setupPage)
        now += 1_000
        assertTrue(repo.edit { it.copy(theme = "light") })
        assertEquals(2, records.state.value.syncedPreferences!!.editCount)
        assertFalse("same settings: no new version", repo.edit { it.copy(theme = "light") })
        assertEquals(2, records.state.value.syncedPreferences!!.editCount)
    }

    @Test fun aRestoredArchiveWithSettingsOpensAsSetUp() = runTest {
        // Android backup restored the archive, but not this device's local flags.
        val restored = PreferencesRules.commit(RecordState(), PreferencesRules.defaults(zone, now).copy(theme = "dark"), now, "00000000-0000-4000-8000-00000000000A")
        Files.createDirectories(archive.parent)
        RecordStore.writeAtomically(archive, RecordArchive.encode(restored, now, zone))
        val (records, _, repo) = open()
        records.load()
        assertTrue(repo.isSetUp.value)
        assertEquals("dark", repo.preferences.value.theme)
    }

    @Test fun invalidEditsAndDamagedLocalFilesAreHarmless() = runTest {
        Files.createDirectories(deviceFile.parent)
        Files.writeString(deviceFile, "{broken")
        val (records, device, repo) = open()
        records.load()
        assertEquals(DeviceSettings(), device.settings.value)
        assertFalse(repo.edit { it.copy(microBreakIntervalMinutes = 0) })
        repo.updateDevice { it.copy(hideEarnings = true) }
        assertTrue(DeviceSettingsStore(deviceFile).settings.value.hideEarnings)
    }
}
