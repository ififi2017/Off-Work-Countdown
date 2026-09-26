package com.rainif.doneat

import android.app.Application
import com.rainif.doneat.core.data.DeviceSettingsStore
import com.rainif.doneat.core.data.FocusStore
import com.rainif.doneat.core.data.RecordStore
import com.rainif.doneat.core.data.SessionStore
import com.rainif.doneat.core.data.SettingsRepository
import com.rainif.doneat.core.domain.records.DayEditDraft
import com.rainif.doneat.core.domain.records.LifeProfileDraft
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.session.ScheduleFieldChange
import com.rainif.doneat.plus.PlusAccess
import com.rainif.doneat.focus.FocusCoordinator
import com.rainif.doneat.timer.TimerCoordinator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
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

    /** Plus, for the pages it gates: charts beyond the free week, Life, history edits and Focus. */
    val plus = PlusAccess(app)

    /** Focus runs on the same archive; its queue of planned starts is device-local, beside the session. */
    val focus = FocusStore(records, sessions.session, plus.authorized, files.resolve("device/focus-queue.json"), newId, { app.getString(R.string.focusTaskTitle) })
    /** A sentence a focus editor leaves for the Focus page to show after it closes. */
    val focusNotice = MutableStateFlow<String?>(null)
    /** The usual-day editor's working copy, shared with the task page it opens. */
    val focusTemplateDraft = MutableStateFlow<com.rainif.doneat.ui.focus.FocusTemplateDraft?>(null)
    val focusCoordinator = FocusCoordinator(app, focus, records, sessions, settings, plus.authorized, scope, nowMs)

    val timer = TimerCoordinator(
        app, sessions, settings, scope, nowMs,
        planChanges = combine(records.state, plus.authorized) { state, plus -> state.focusPlanningConfiguration to plus },
        adjust = { prefs -> focusCoordinator.breakTakeover(records.state.value, prefs.microBreakEnabled) },
    )

    /** The home-screen widget's snapshot: rebuilt with the session, never with money in it. */
    val widgets = com.rainif.doneat.widget.WidgetCoordinator(app, sessions, scope, nowMs)

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

    /** The Records day editor's unsaved draft, kept like [scheduleDraft] so rotation never loses it. */
    val dayEditDraft = MutableStateFlow<DayEditDraft?>(null)

    /** The Life profile editor's unsaved fields, likewise. */
    val lifeEditDraft = MutableStateFlow<LifeProfileDraft?>(null)

    private val _loaded = MutableStateFlow(false)
    /** False until the archive has been read: until then nothing can tell setup from a restored install. */
    val loaded: StateFlow<Boolean> = _loaded.asStateFlow()

    init {
        scope.launch {
            records.load()
            sessions.load()
            timer.reconcile()
            focusCoordinator.reconcile()
            _loaded.value = true
            timer.start()
            focusCoordinator.start()
            widgets.start()
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
