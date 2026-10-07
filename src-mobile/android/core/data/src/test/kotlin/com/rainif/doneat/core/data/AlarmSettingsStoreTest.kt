package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.alarms.ShiftAlarmSettings
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files
import java.util.UUID

class AlarmSettingsStoreTest {
    @Test fun defaultsAreOffAndDeviceFileRoundtripsPerTypeWithoutArchiveFields() = runTest {
        val path = Files.createTempDirectory("alarm-settings").resolve("settings.json")
        val first = AlarmSettingsStore(path)
        assertFalse(first.settings.value.enabled)
        val type = UUID.randomUUID()
        val next = ShiftAlarmSettings(true, 90, mapOf(type to 150), setOf(UUID.randomUUID()))
        assertTrue(first.update { next })
        assertEquals(next, AlarmSettingsStore(path).settings.value)
        assertFalse(Files.readString(path).contains("salary"))
        assertFalse(Files.readString(path).contains("syncedPreferences"))
    }
    @Test fun corruptSettingsFailClosedAndInvalidLeadNeverPersists() = runTest {
        val path = Files.createTempDirectory("alarm-settings").resolve("settings.json")
        Files.writeString(path, "{broken")
        val store = AlarmSettingsStore(path)
        assertFalse(store.settings.value.enabled)
        assertFalse(store.update { it.copy(enabled = true, defaultLeadMinutes = 1) })
        assertFalse(store.settings.value.enabled)
    }
    @Test fun persistenceFailureKeepsInMemoryDisabledAndCannotArmAnything() = runTest {
        val directory = Files.createTempDirectory("alarm-settings-blocked")
        val blocked = directory.resolve("not-a-directory")
        Files.writeString(blocked, "blocked")
        val store = AlarmSettingsStore(blocked.resolve("settings.json"))
        assertFalse(store.update { it.copy(enabled = true) })
        assertFalse(store.settings.value.enabled)
    }

}
