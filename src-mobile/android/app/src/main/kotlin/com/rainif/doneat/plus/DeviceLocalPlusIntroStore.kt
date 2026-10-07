package com.rainif.doneat.plus

import com.rainif.doneat.core.data.RecordStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.nio.file.Files
import java.nio.file.Path

/** A tiny noBackup marker. It never enters the archive, release notes metadata or Play evidence. */
internal class DeviceLocalPlusIntroStore(private val file: Path) {
    private val lock = Mutex()
    private val mutableState = MutableStateFlow(PlusIntroState())
    val state = mutableState.asStateFlow()

    suspend fun initialize(existingSetup: Boolean) = withContext(Dispatchers.IO) {
        lock.withLock {
            if (mutableState.value.loaded) return@withLock
            var damaged = false
            val stored = try {
                if (!Files.exists(file)) null else when (Files.readAllBytes(file).toString(Charsets.UTF_8)) {
                    "seen" -> true
                    "unseen" -> false
                    else -> { damaged = true; null }
                }
            } catch (_: Exception) { damaged = true; null }
            val seen = PlusIntroPolicy.initialSeen(existingSetup, stored, damaged)
            val persisted = if (stored == null && !damaged) save(seen) else !damaged
            mutableState.value = PlusIntroState(loaded = true, seen = seen, writeFailed = !persisted)
        }
    }

    suspend fun markSeen() = withContext(Dispatchers.IO) {
        lock.withLock {
            if (!mutableState.value.loaded) return@withLock
            mutableState.value = PlusIntroPolicy.afterFinish(mutableState.value, save(true))
        }
    }

    private fun save(seen: Boolean): Boolean = runCatching {
        val bytes = (if (seen) "seen" else "unseen").toByteArray(Charsets.UTF_8)
        Files.createDirectories(file.parent)
        RecordStore.writeAtomically(file, bytes)
        Files.readAllBytes(file).contentEquals(bytes)
    }.getOrDefault(false)
}
