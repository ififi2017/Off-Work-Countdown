package com.rainif.doneat.plus

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files

class DeviceLocalPlusIntroStoreTest {
    @Test fun freshMarkerSurvivesCompletionRelaunchWithoutBeingMistakenForUpgrade() = runBlocking {
        val directory = Files.createTempDirectory("plus-intro")
        try {
            val file = directory.resolve("intro")
            val first = DeviceLocalPlusIntroStore(file)
            first.initialize(existingSetup = false)
            assertFalse(first.state.value.seen)
            first.initialize(existingSetup = true)
            assertFalse(first.state.value.seen)
            val second = DeviceLocalPlusIntroStore(file)
            second.initialize(existingSetup = true)
            assertFalse(second.state.value.seen)
            second.markSeen()
            val third = DeviceLocalPlusIntroStore(file)
            third.initialize(existingSetup = true)
            assertTrue(third.state.value.seen)
        } finally { directory.toFile().deleteRecursively() }
    }

    @Test fun initialExistingSetupSkipsIntroAndPersistsMigration() = runBlocking {
        val directory = Files.createTempDirectory("plus-intro")
        try {
            val file = directory.resolve("intro")
            val first = DeviceLocalPlusIntroStore(file)
            first.initialize(existingSetup = true)
            assertTrue(first.state.value.seen)
            assertEquals("seen", Files.readString(file))
        } finally { directory.toFile().deleteRecursively() }
    }

    @Test fun damagedMetadataSkipsAnUnexpectedNewIntro() = runBlocking {
        val directory = Files.createTempDirectory("plus-intro")
        try {
            val file = directory.resolve("intro")
            Files.writeString(file, "damaged")
            val store = DeviceLocalPlusIntroStore(file)
            store.initialize(existingSetup = false)
            assertTrue(store.state.value.loaded); assertTrue(store.state.value.seen)
            assertTrue(store.state.value.writeFailed)
        } finally { directory.toFile().deleteRecursively() }
    }

    @Test fun writeFailureFinishesInMemoryWithoutTouchingArchiveOrLooping() = runBlocking {
        val directory = Files.createTempDirectory("plus-intro")
        try {
            val parentFile = directory.resolve("not-a-directory")
            Files.writeString(parentFile, "preserve")
            val store = DeviceLocalPlusIntroStore(parentFile.resolve("intro"))
            store.initialize(existingSetup = false)
            store.markSeen()
            assertTrue(store.state.value.loaded); assertTrue(store.state.value.seen)
            assertTrue(store.state.value.writeFailed)
            assertEquals("preserve", Files.readString(parentFile))
        } finally { directory.toFile().deleteRecursively() }
    }
}
