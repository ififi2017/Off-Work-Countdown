package com.rainif.doneat

import android.app.Application
import com.rainif.doneat.core.data.DeviceSettingsStore
import com.rainif.doneat.core.data.RecordStore
import com.rainif.doneat.core.data.SessionStore
import com.rainif.doneat.core.data.SettingsRepository
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.session.ScheduleFieldChange
import com.rainif.doneat.plus.PlusAccess
import com.rainif.doneat.timer.TimerCoordinator
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

    private val _holidays = MutableStateFlow(HolidayCalendar.EMPTY)
    /** The bundled holiday dataset (shared with iOS); read once, off the main thread. */
    val holidays: StateFlow<HolidayCalendar> = _holidays.asStateFlow()

    /** The running countdown; its state file is device-local, beside the device settings. */
    val sessions = SessionStore(files.resolve("device/session.json"), records, settings, scope, holidays, systemZone, newId)
    val timer = TimerCoordinator(app, sessions, settings, scope, nowMs)

    /** Plus, for the pages it gates: charts beyond the free week, Life and history edits. */
    val plus = PlusAccess(app)

    /**
     * The completed run already celebrated in this process. Kept in memory only:
     * switching tabs never replays it, a cold launch may celebrate once more.
     */
    @Volatile var lastCelebratedEndAtMs = 0.0

    /**
     * The schedule page's unsaved draft (iOS keeps it on the scene), so
     * rotating, or opening a shift type from the page, never loses it.
     */
    val scheduleDraft = MutableStateFlow(ScheduleFieldChange())

    private val _loaded = MutableStateFlow(false)
    /** False until the archive has been read: until then nothing can tell setup from a restored install. */
    val loaded: StateFlow<Boolean> = _loaded.asStateFlow()

    init {
        scope.launch {
            records.load()
            sessions.load()
            timer.reconcile()
            _loaded.value = true
            timer.start()
        }
        scope.launch(Dispatchers.IO) {
            // A damaged or missing dataset only turns holiday assignments off; the schedule still runs.
            runCatching { app.assets.open("HolidayTemplates.json").use { HolidayCalendar.parse(it.readBytes().decodeToString()) } }
                .onSuccess { _holidays.value = it }
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
