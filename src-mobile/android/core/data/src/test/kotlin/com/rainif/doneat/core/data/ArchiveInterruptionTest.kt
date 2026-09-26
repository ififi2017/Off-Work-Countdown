package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.RecordJson
import com.rainif.doneat.core.domain.records.RecordState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID
import java.util.concurrent.TimeUnit
import java.util.concurrent.CountDownLatch

class ArchiveInterruptionTest {
    @get:Rule val folder = TemporaryFolder()
    private val now = 1_790_000_000_000.0
    private fun seed(): RecordState = RecordJson.apply(
        RecordJson.decode(File(System.getProperty("owc.syntheticArchives"), "v6.json").readText()),
        RecordState(), RecordJson.ImportMode.SKIP_ERASED,
    ).first

    @Test fun killingALargeImportBeforeAndAfterReplacementLeavesOneCompleteArchive() = runBlocking {
        val original = seed()
        val task = original.focusTasks.single()
        val incoming = original.copy(focusTasks = (1..10_000).map {
            task.copy(id = UUID.nameUUIDFromBytes("import-$it".toByteArray()).toString())
        })
        val backup = folder.root.toPath().resolve("import.json")
        Files.writeString(backup, RecordsTransfer.export(incoming, true, now, "UTC"))
        val before = RecordArchive.encode(original, now, "UTC")
        for (phase in listOf("before", "after")) {
            val file = folder.root.toPath().resolve("$phase.json")
            Files.write(file, before)
            val marker = folder.root.toPath().resolve("$phase.ready")
            val log = folder.root.toPath().resolve("$phase.log").toFile()
            val child = ProcessBuilder(
                File(System.getProperty("java.home"), "bin/java").absolutePath,
                "-cp", System.getProperty("owc.testClasspath"), ArchiveImportProcess::class.java.name,
                file.toString(), backup.toString(), phase, marker.toString(),
            ).redirectErrorStream(true).redirectOutput(log).start()
            try {
                val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(30)
                while (!Files.exists(marker) && child.isAlive && System.nanoTime() < deadline) Thread.sleep(10)
                assertTrue("child reached $phase replacement: ${log.readText()}", Files.exists(marker))
                child.destroyForcibly()
                assertTrue(child.waitFor(10, TimeUnit.SECONDS))
            } finally {
                if (child.isAlive) child.destroyForcibly().waitFor(10, TimeUnit.SECONDS)
            }
            val reopened = RecordStore(file, { now }, { "UTC" })
            reopened.load()
            assertNull(reopened.persistenceError.value)
            if (phase == "before") {
                assertArrayEquals(before, Files.readAllBytes(file))
                assertEquals(original, reopened.state.value)
            } else {
                assertEquals(10_001, reopened.state.value.focusTasks.size)
                assertEquals(original.periods, reopened.state.value.periods)
                assertEquals(original.observations, reopened.state.value.observations)
                assertNotNull(RecordsTransfer.commit(reopened, Files.readAllBytes(backup)))
                assertEquals("retry does not duplicate imported rows", 10_001, reopened.state.value.focusTasks.size)
            }
        }
    }

    @Test fun backupsDuringReplacementAlwaysReadACompleteOldOrNewArchive() = runBlocking {
        val original = seed()
        val task = original.focusTasks.single()
        val large = original.copy(focusTasks = (1..5_000).map {
            task.copy(id = UUID.nameUUIDFromBytes("backup-$it".toByteArray()).toString())
        })
        val old = RecordArchive.encode(original, now, "UTC")
        val newer = RecordArchive.encode(large, now, "UTC")
        val file = folder.root.toPath().resolve("records.json")
        Files.write(file, old)
        val start = CountDownLatch(1)
        val writer = async(Dispatchers.IO) {
            assertTrue(start.await(10, TimeUnit.SECONDS))
            repeat(40) { RecordStore.writeAtomically(file, if (it % 2 == 0) newer else old) }
        }
        val snapshots = async(Dispatchers.IO) {
            start.countDown()
            repeat(200) {
                val copied = Files.readAllBytes(file)
                assertTrue("a backup is exactly one committed revision", copied.contentEquals(old) || copied.contentEquals(newer))
                // Decode actual copies too; a partial import is never a restorable archive.
                if (it % 20 == 0) assertTrue(RecordArchive.decode(copied, now).focusTasks.size in listOf(1, 5_000))
            }
        }
        writer.await()
        snapshots.await()
    }
}

/** A disposable JVM process; the parent kills it inside a real import's file commit. */
object ArchiveImportProcess {
    @JvmStatic fun main(args: Array<String>) = runBlocking {
        val target = Path.of(args[0])
        val store = RecordStore(target, { 1_790_000_000_000.0 }, { "UTC" }, writeFile = { path, bytes ->
            fun waitForKill() {
                Files.writeString(Path.of(args[3]), "ready")
                CountDownLatch(1).await()
            }
            if (args[2] == "before") waitForKill()
            RecordStore.writeAtomically(path, bytes)
            if (args[2] == "after") waitForKill()
        })
        store.load()
        check(RecordsTransfer.commit(store, Files.readAllBytes(Path.of(args[1]))) != null)
    }
}
