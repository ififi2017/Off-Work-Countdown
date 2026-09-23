package com.rainif.doneat.core.data

import com.rainif.doneat.core.domain.records.RecordState
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.AccessDeniedException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.util.UUID

enum class RecordPersistenceError {
    /** The file exists but does not decode. Writes stay blocked until it is quarantined. */
    INVALID_ARCHIVE,

    /** The file could not be read at all. Writes stay blocked too. */
    UNREADABLE_ARCHIVE,

    /** The last write did not land; the previous archive is intact and writes may retry. */
    WRITE_FAILED,
}

sealed interface WriteResult<out T> {
    data class Saved<T>(val value: T) : WriteResult<T>
    data object Blocked : WriteResult<Nothing>
    data class Failed(val cause: Throwable) : WriteResult<Nothing>
}

/**
 * Serialises every records write (iOS `RecordCoordinator`). A change is
 * computed on the current archive, encoded, validated and atomically written;
 * only then is it published. A failure at any step leaves both the published
 * state and the file exactly as they were, so the caller keeps its draft.
 *
 * A damaged archive is never treated as an empty first launch: it blocks
 * writes until [quarantine] moves it aside.
 */
class RecordStore(
    private val file: Path,
    private val nowMs: () -> Double,
    /** The records zone, used when the archive has no career period to name one. */
    private val fallbackZone: () -> String,
    private val io: CoroutineDispatcher = Dispatchers.IO,
    private val writeFile: (Path, ByteArray) -> Unit = ::writeAtomically,
) {
    private val mutex = Mutex()
    private val _state = MutableStateFlow(RecordState())
    private val _error = MutableStateFlow<RecordPersistenceError?>(null)

    val state: StateFlow<RecordState> = _state.asStateFlow()
    val persistenceError: StateFlow<RecordPersistenceError?> = _error.asStateFlow()

    val blocksWrites: Boolean
        get() = _error.value == RecordPersistenceError.INVALID_ARCHIVE || _error.value == RecordPersistenceError.UNREADABLE_ARCHIVE

    suspend fun load() = mutex.withLock {
        withContext(io) {
            val bytes = try {
                if (!Files.exists(file)) null else Files.readAllBytes(file)
            } catch (e: IOException) {
                _error.value = RecordPersistenceError.UNREADABLE_ARCHIVE
                return@withContext
            }
            if (bytes == null) {
                _state.value = RecordState()
                _error.value = null
                return@withContext
            }
            try {
                _state.value = RecordArchive.decode(bytes, nowMs())
                _error.value = null
            } catch (e: RecordArchive.InvalidArchive) {
                _error.value = RecordPersistenceError.INVALID_ARCHIVE
            }
        }
    }

    /**
     * Applies [change] to the current archive and saves it. [change] runs under
     * the store's lock and must be pure: it may run and be discarded.
     */
    suspend fun <T> update(change: (RecordState) -> Pair<RecordState, T>): WriteResult<T> = mutex.withLock {
        if (blocksWrites) return@withLock WriteResult.Blocked
        val (next, value) = change(_state.value)
        if (next == _state.value) return@withLock WriteResult.Saved(value)
        try {
            withContext(io) {
                writeFile(file, RecordArchive.encode(next, nowMs(), fallbackZone()))
            }
        } catch (e: Exception) {
            _error.value = RecordPersistenceError.WRITE_FAILED
            return@withLock WriteResult.Failed(e)
        }
        _state.value = next
        _error.value = null
        WriteResult.Saved(value)
    }

    /** Moves a damaged archive aside (never deletes it) and starts empty. Returns where it went. */
    suspend fun quarantine(): Path? = mutex.withLock {
        withContext(io) {
            val moved = if (Files.exists(file)) {
                val target = file.resolveSibling("${file.fileName}.damaged-${nowMs().toLong()}")
                Files.move(file, target)
                target
            } else {
                null
            }
            _state.value = RecordState()
            _error.value = null
            moved
        }
    }

    companion object {
        /**
         * Write-then-rename in the same directory: readers see the old file or
         * the new one, never a torn write. The data is forced to storage before
         * the rename, and a failed attempt leaves no pending file behind.
         */
        fun writeAtomically(target: Path, bytes: ByteArray) {
            val directory = target.toAbsolutePath().parent
            Files.createDirectories(directory)
            val pending = directory.resolve(".${target.fileName}.${UUID.randomUUID()}.pending")
            try {
                FileChannel.open(pending, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE).use { channel ->
                    val buffer = ByteBuffer.wrap(bytes)
                    while (buffer.hasRemaining()) channel.write(buffer)
                    channel.force(true)
                }
                Files.move(pending, target, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            } catch (e: Exception) {
                runCatching { Files.deleteIfExists(pending) }
                throw if (e is AccessDeniedException) IOException("archive not writable", e) else e
            }
        }
    }
}
