package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.WorkObservationKind
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.session.TimerPhase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.nio.file.Files
import java.time.LocalDateTime
import java.time.ZoneOffset

@OptIn(ExperimentalCoroutinesApi::class)
class SessionStoreTest {
    @get:Rule val folder = TemporaryFolder()
    private val zone = "UTC"
    private var ids = 0
    private val archive by lazy { folder.root.toPath().resolve("records/records.json") }
    private val sessionFile by lazy { folder.root.toPath().resolve("device/session.json") }

    private fun at(day: Int, hour: Int) = LocalDateTime.of(2026, 8, day, hour, 0).toInstant(ZoneOffset.UTC).toEpochMilli().toDouble()

    private class Opened(val records: RecordStore, val settings: SettingsRepository, val session: SessionStore)

    private suspend fun TestScope.open(setUp: Boolean = true): Opened {
        val dispatcher = UnconfinedTestDispatcher(testScheduler)
        val records = RecordStore(archive, { at(24, 8) }, { zone }, dispatcher)
        val device = DeviceSettingsStore(folder.root.toPath().resolve("device/settings.json"))
        val scope = CoroutineScope(backgroundScope.coroutineContext + dispatcher)
        val newId = { "00000000-0000-4000-8000-%012d".format(++ids) }
        val settings = SettingsRepository(records, device, scope, { at(24, 8) }, { zone }, newId)
        val session = SessionStore(sessionFile, records, settings, scope, MutableStateFlow(HolidayCalendar.EMPTY), { zone }, newId, dispatcher)
        records.load()
        if (setUp && !settings.isSetUp.value) {
            settings.edit { it.copy(workdays = listOf(1, 2, 3, 4, 5), startMinutes = 9 * 60, endMinutes = 17 * 60, lunchEnabled = false) }
            settings.completeSetup()
        }
        session.load()
        return Opened(records, settings, session)
    }

    @Test fun aSetUpScheduleArmsOnItsFirstLaunch() = runTest {
        val app = open()
        assertTrue(app.session.state.value.countdownStarted)
        assertTrue(Files.exists(sessionFile))
    }

    @Test fun marksSurviveARelaunch() = runTest {
        run {
            val app = open()
            assertTrue(app.session.run(at(29, 11)) { start(it, at(29, 11), force = true) })
            assertTrue(app.session.run(at(29, 15)) { clockOffEarly(it, at(29, 15)) })
        }
        val app = open()
        val state = app.session.state.value
        assertEquals("2026-08-29", state.forcedWorkdayDate)
        assertEquals(at(29, 15), state.earlyOffAtMs!!, 0.0)
        assertNotNull("the frozen clock-off survives", state.earlyOffSnapshot)
        assertEquals(TimerPhase.COMPLETED, app.session.session.value.visualPhase(at(29, 16)))
    }

    @Test fun aCommandAndItsArchiveWritesLandTogether() = runTest {
        val app = open()
        assertTrue(app.session.run(at(24, 8)) { clockInEarly(it, at(24, 8)) })
        val archive = app.records.state.value
        assertEquals(listOf(WorkObservationKind.COUNTDOWN_STARTED), archive.observations.map { it.kind })
        assertEquals(1, archive.overrides.size)
        assertFalse("a repeat is refused", app.session.run(at(24, 8)) { clockInEarly(it, at(24, 8)) })
        assertEquals(archive, app.records.state.value)
    }

    @Test fun aDamagedArchiveRefusesEveryCommandAndLeavesTheSessionAlone() = runTest {
        run { open() }
        Files.writeString(archive, "damaged")
        val app = open(setUp = false)
        assertTrue(app.records.blocksWrites)
        val before = app.session.state.value
        val file = Files.readString(sessionFile)
        assertFalse(app.session.run(at(24, 10)) { clockOffEarly(it, at(24, 10)) })
        assertFalse(app.session.run(at(24, 8)) { clockInEarly(it, at(24, 8)) })
        assertEquals(before, app.session.state.value)
        assertEquals(file, Files.readString(sessionFile))
        assertEquals("damaged", Files.readString(archive))
    }

    @Test fun aDamagedSessionFileReadsAsAFreshSession() = runTest {
        run { open() }
        Files.writeString(sessionFile, "{not json")
        val app = open()
        assertNull(app.session.state.value.earlyOffAtMs)
        assertFalse(app.session.state.value.countdownStarted)
    }
}
