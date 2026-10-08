package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.settings.PreferencesRules
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
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

    @Test fun holidayDraftPersistsAndCompletesInTheSameArchiveWrite() = runTest {
        val (records, device, repo) = open()
        records.load()
        repo.edit { it.copy(endMinutes = 18 * 60, lunchEnabled = true) }
        repo.updateDevice { it.copy(setupHolidayRegionIdentifier = "CN", setupPage = "GLANCE") }
        assertEquals("CN", DeviceSettingsStore(deviceFile).settings.value.setupHolidayRegionIdentifier)
        assertNull(records.state.value.extendedSchedule)
        assertTrue(repo.completeSetup(com.rainif.doneat.core.domain.schedule.HolidayCalendar.EMPTY, "Day shift", "Rest"))
        val saved = records.state.value
        assertEquals("CN", saved.extendedSchedule!!.content.holidayRegionIdentifier)
        assertEquals(18 * 60, saved.extendedSchedule!!.content.shiftTypes.first { it.kind == com.rainif.doneat.core.domain.schedule.ShiftType.Kind.WORK }.endMinutes)
        assertTrue(saved.extendedSchedule!!.content.isValid)
        assertNull(device.settings.value.setupHolidayRegionIdentifier)
        assertTrue(repo.completeSetup(com.rainif.doneat.core.domain.schedule.HolidayCalendar.EMPTY))
        assertEquals(saved, records.state.value)
    }

    @Test fun failedSetupWriteKeepsTheDraftAndTheSeedTogetherForRetry() = runTest {
        val dispatcher = UnconfinedTestDispatcher(testScheduler)
        var fails = true
        var writes = 0
        val records = RecordStore(archive, { now }, { zone }, dispatcher) { path, bytes ->
            writes++
            if (fails) throw java.io.IOException("test failed write")
            RecordStore.writeAtomically(path, bytes)
        }
        val device = DeviceSettingsStore(deviceFile)
        val repo = SettingsRepository(records, device, CoroutineScope(backgroundScope.coroutineContext + dispatcher),
            { now }, { zone }, { "00000000-0000-4000-8000-%012d".format(++ids) })
        records.load()
        repo.edit { it.copy(endMinutes = 18 * 60) }
        repo.updateDevice { it.copy(setupHolidayRegionIdentifier = "CN", setupPage = "READY") }
        assertFalse(repo.completeSetup(com.rainif.doneat.core.domain.schedule.HolidayCalendar.EMPTY))
        assertNull(records.state.value.syncedPreferences)
        assertNull(records.state.value.extendedSchedule)
        assertFalse(device.settings.value.onboardingComplete)
        assertEquals("CN", device.settings.value.setupHolidayRegionIdentifier)
        assertEquals(18 * 60, device.settings.value.setupDraft!!.endMinutes)
        assertFalse(Files.exists(archive))
        fails = false
        assertTrue(repo.completeSetup(com.rainif.doneat.core.domain.schedule.HolidayCalendar.EMPTY))
        assertEquals(2, writes)
        assertTrue(device.settings.value.onboardingComplete)
        assertEquals("CN", records.state.value.extendedSchedule!!.content.holidayRegionIdentifier)
    }

    @Test fun reportNotificationMigrationReadsRestoredArchiveBeforeDerivedFlowCatchesUp() = runTest {
        val (records, device, original) = open()
        records.load()
        original.edit { it.copy(cycleEndSummaryNotificationEnabled = true) }
        original.completeSetup()
        val delayed = SettingsRepository(records, device, backgroundScope, { now }, { zone }, { "00000000-0000-4000-8000-000000000999" })
        delayed.migrateCycleReportNotifications()
        assertTrue(device.settings.value.weeklyReportEnabled)
        assertFalse(device.settings.value.monthlyReportEnabled)
        assertFalse(device.settings.value.yearlyReportEnabled)
        assertTrue(device.settings.value.reportNotificationMigrationComplete)
        assertFalse(records.state.value.syncedPreferences!!.cycleEndSummaryNotificationEnabled)
        delayed.updateDevice { it.copy(weeklyReportEnabled = false) }
        delayed.migrateCycleReportNotifications()
        assertFalse(device.settings.value.weeklyReportEnabled)
        val restored = DeviceSettingsStore(deviceFile).settings.value
        assertTrue(restored.reportNotificationMigrationComplete)
        assertFalse(restored.weeklyReportEnabled)
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

    @Test fun customAccentSurvivesRestartAndStaysOutsideTheRecordArchive() = runTest {
        val (records, _, repo) = open()
        records.load()
        repo.completeSetup()
        val before = Files.readString(archive)
        repo.updateDevice { it.copy(accentColor = 0x2563EB, dynamicColor = false) }
        assertEquals(0x2563EB, DeviceSettingsStore(deviceFile).settings.value.accentColor)
        repo.updateDevice { it.copy(dynamicColor = true) }
        val restored = DeviceSettingsStore(deviceFile).settings.value
        assertTrue(restored.dynamicColor)
        assertEquals(0x2563EB, restored.accentColor)
        assertEquals("device-only choice does not edit records", before, Files.readString(archive))
        repo.updateDevice { it.copy(accentColor = null, dynamicColor = false) }
        assertNull(DeviceSettingsStore(deviceFile).settings.value.accentColor)
    }

    @Test fun calendarWeekStartPersistsAndControlsGridReportsAndFutureNotifications() = runTest {
        val (records, device, repo) = open()
        records.load()
        repo.completeSetup()
        val archiveBefore = Files.readString(archive)
        val us = java.util.Locale.US
        val de = java.util.Locale.GERMANY
        assertEquals(java.time.DayOfWeek.SUNDAY, device.settings.value.calendarFirstDay(us))
        assertEquals(java.time.DayOfWeek.MONDAY, device.settings.value.calendarFirstDay(de))
        val zone = java.time.ZoneId.of("UTC")
        val date = java.time.LocalDate.parse("2026-10-01")
        val instant = java.time.Instant.parse("2026-10-03T12:00:00Z").toEpochMilli().toDouble()
        suspend fun choose(day: Int): Pair<com.rainif.doneat.core.domain.records.CycleReportPeriod, Long> {
            repo.updateDevice { it.copy(calendarWeekStart = day) }
            val restored = DeviceSettingsStore(deviceFile).settings.value
            assertEquals(day, restored.calendarFirstDay(us).value)
            assertEquals(day, restored.calendarFirstDay(de).value)
            val queries = com.rainif.doneat.core.domain.records.RecordsQueries(records.state.value,
                com.rainif.doneat.core.domain.schedule.HolidayCalendar.EMPTY, zone, true,
                firstDayOfWeek = restored.calendarFirstDay(de))
            assertEquals(if (day == 7) 4 else 3, queries.gridLeadingBlanks(date))
            val period = queries.reportPeriod(com.rainif.doneat.core.domain.records.CycleReportKind.WEEK, date)
            val notification = com.rainif.doneat.core.domain.records.CycleReportNotificationPlan.items(
                true, false, false, instant, zone, restored.calendarFirstDay(de)).single()
            assertEquals(period, notification)
            return period to notification.notificationAtMs
        }
        val sunday = choose(7)
        val monday = choose(1)
        assertEquals("2026-09-27", sunday.first.startDayKey)
        assertEquals("2026-09-28", monday.first.startDayKey)
        assertEquals(java.time.Instant.parse("2026-10-04T09:00:00Z").toEpochMilli(), sunday.second)
        assertEquals(java.time.Instant.parse("2026-10-05T09:00:00Z").toEpochMilli(), monday.second)
        assertEquals(sunday.first, com.rainif.doneat.core.domain.records.CycleReportPeriod.fromUrl(sunday.first.url))
        assertEquals("calendar layout never edits a saved roster or the schema 7 archive", archiveBefore, Files.readString(archive))
    }

    @Test fun invalidWeekStartPreservesOtherSettingsAndFallsBackToLocale() {
        Files.createDirectories(deviceFile.parent)
        for (value in listOf("null", "0", "6", "8", "\"invalid\"", "{}")) {
            Files.writeString(deviceFile, "{\"hideEarnings\":true,\"calendarWeekStart\":$value}")
            val local = DeviceSettingsStore(deviceFile).settings.value
            assertNull(local.calendarWeekStart)
            assertTrue(local.hideEarnings)
            assertEquals(java.time.DayOfWeek.MONDAY, local.calendarFirstDay(java.util.Locale.GERMANY))
        }
    }

    @Test fun missingOrInvalidAccentDoesNotDiscardOtherLocalSettings() {
        Files.createDirectories(deviceFile.parent)
        for (value in listOf("null", "-1", "16777216", "\"blue\"", "{}")) {
            Files.writeString(deviceFile, "{\"hideEarnings\":true,\"accentColor\":$value}")
            val settings = DeviceSettingsStore(deviceFile).settings.value
            assertNull(settings.accentColor)
            assertTrue(settings.hideEarnings)
        }
        Files.writeString(deviceFile, "{\"hideEarnings\":true}")
        assertNull(DeviceSettingsStore(deviceFile).settings.value.accentColor)
        assertTrue(DeviceSettingsStore(deviceFile).settings.value.hideEarnings)
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

    @Test fun resultSetsReserveExactlyThreeTrialsAndPersistBeforeReturning() = runTest {
        val (records, _, repo) = open()
        records.load()
        val before = records.state.value
        val allowed = (1..12).map { async { repo.consumeLeavePlannerTrial() } }.awaitAll()
        assertEquals(3, allowed.count { it })
        assertEquals(3, repo.device.value.leavePlannerTrialsUsed)
        assertEquals(0, repo.device.value.leavePlannerTrialsLeft)
        val restarted = DeviceSettingsStore(deviceFile)
        assertEquals(3, restarted.settings.value.leavePlannerTrialsUsed)
        assertFalse(restarted.consumeLeavePlannerTrial())
        assertEquals("trial views never write business records", before, records.state.value)
    }

    @Test fun existingTwoUsedTrialsKeepOneResultSetAfterRestart() = runTest {
        val (_, _, repo) = open()
        repo.updateDevice { it.copy(leavePlannerTrialsUsed = 2) }
        val restarted = DeviceSettingsStore(deviceFile)
        assertEquals(1, restarted.settings.value.leavePlannerTrialsLeft)
        assertTrue(restarted.consumeLeavePlannerTrial())
        assertEquals(3, restarted.settings.value.leavePlannerTrialsUsed)
        assertEquals(0, DeviceSettingsStore(deviceFile).settings.value.leavePlannerTrialsLeft)
    }

    @Test fun failedTrialPersistenceDoesNotConsumeAView() = runTest {
        val (_, _, repo) = open()
        Files.createDirectories(deviceFile.parent)
        Files.createDirectory(deviceFile)
        assertTrue(runCatching { repo.consumeLeavePlannerTrial() }.isFailure)
        assertEquals(3, repo.device.value.leavePlannerTrialsLeft)
    }
}
