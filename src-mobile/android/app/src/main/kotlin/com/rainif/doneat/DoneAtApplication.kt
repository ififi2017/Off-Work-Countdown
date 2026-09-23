package com.rainif.doneat

import android.app.Application
import com.rainif.doneat.core.data.DeviceSettingsStore
import com.rainif.doneat.core.data.RecordStore
import com.rainif.doneat.core.data.SettingsRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

/**
 * The app's single set of stores (iOS `AppRuntime`). Created once per process;
 * screens reach it through [DoneAtApplication.graph].
 */
class AppGraph(app: Application) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val files = app.filesDir.toPath()

    val nowMs: () -> Double = { System.currentTimeMillis().toDouble() }
    val systemZone: () -> String = { ZoneId.systemDefault().id }
    val newId: () -> String = { UUID.randomUUID().toString().uppercase(Locale.ROOT) }

    /** The records archive (D-13): included in Android backup and device transfer. */
    val records = RecordStore(files.resolve("records/records.json"), nowMs, systemZone)
    val device = DeviceSettingsStore(files.resolve("device/settings.json"))
    val settings = SettingsRepository(records, device, scope, nowMs, systemZone, newId)

    private val _loaded = MutableStateFlow(false)
    /** False until the archive has been read: until then nothing can tell setup from a restored install. */
    val loaded: StateFlow<Boolean> = _loaded.asStateFlow()

    init {
        scope.launch {
            records.load()
            _loaded.value = true
        }
    }
}

class DoneAtApplication : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        graph = AppGraph(this)
    }
}
