package com.rainif.doneat.ui.release

import android.content.Context
import android.util.AtomicFile
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** Not part of schema 7, Auto Backup, device transfer, or the settings draft. */
class DeviceLocalReleaseNotesStore(context: Context) {
    private val file = AtomicFile(File(context.applicationContext.noBackupFilesDir, "release-notes.json"))
    private val lock = Mutex()
    private val mutableState = MutableStateFlow(ReleaseNotesState())
    val state: StateFlow<ReleaseNotesState> = mutableState.asStateFlow()

    /** Wait for AppGraph.loaded, then pass SettingsRepository.isSetUp (restores count as setup). */
    suspend fun initialize(onboardingComplete: Boolean) = withContext(Dispatchers.IO) {
        lock.withLock {
            if (mutableState.value.loaded) return@withLock
            var readFailed = false
            val seen = try {
                if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists() &&
                    !File(file.baseFile.path + ".new").exists()) null
                else JSONObject(file.openRead().bufferedReader().use { it.readText() })
                    .getString("seenRelease").also { require(it.isNotBlank() && it.length <= 64) }
            } catch (_: Exception) {
                // Unknown/corrupt metadata cannot silently suppress an existing user's introduction.
                readFailed = true
                null
            }
            var next = ReleaseNotesState(loaded = true, seenRelease = seen, writeFailed = readFailed)
            if (ReleaseNotesPolicy.marksSeenOnInitialLoad(onboardingComplete)) {
                next = ReleaseNotesPolicy.afterMarkSeen(next, saveCurrent())
            }
            mutableState.value = next
        }
    }

    /** Only Continue calls this for an existing user; failure leaves the gate open and retryable. */
    suspend fun markSeen(): Boolean = withContext(Dispatchers.IO) {
        lock.withLock {
            if (!mutableState.value.loaded) return@withLock false
            val saved = saveCurrent()
            mutableState.value = ReleaseNotesPolicy.afterMarkSeen(mutableState.value, saved)
            saved
        }
    }

    private fun saveCurrent(): Boolean = try {
        val bytes = JSONObject().put("seenRelease", ReleaseNotesPolicy.CURRENT).toString().toByteArray(Charsets.UTF_8)
        val stream = file.startWrite()
        try {
            stream.write(bytes)
            // AtomicFile.finishWrite logs some sync/rename failures instead
            // of throwing. Explicit sync + read-back keep Continue gated.
            stream.fd.sync()
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
        JSONObject(file.openRead().bufferedReader().use { it.readText() })
            .getString("seenRelease") == ReleaseNotesPolicy.CURRENT
    } catch (_: Exception) {
        false
    }
}
