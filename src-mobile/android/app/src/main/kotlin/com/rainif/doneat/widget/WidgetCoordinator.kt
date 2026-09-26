package com.rainif.doneat.widget

import android.content.Context
import android.content.res.Configuration
import android.os.LocaleList
import android.text.format.DateFormat
import com.rainif.doneat.core.data.SessionStore
import com.rainif.doneat.core.domain.schedule.ScheduleRules
import com.rainif.doneat.core.domain.session.UpcomingTimeline
import com.rainif.doneat.core.domain.widget.WidgetSnapshot
import com.rainif.doneat.core.domain.widget.WidgetSnapshotComposer
import com.rainif.doneat.core.domain.widget.WidgetUpcoming
import com.rainif.doneat.core.domain.settings.AppLanguages
import com.rainif.doneat.timer.TimerCoordinator
import com.rainif.doneat.ui.AppLocale
import com.rainif.doneat.ui.timer.TimerText
import com.rainif.doneat.ui.timer.timelineWords
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale

/**
 * Keeps the home-screen widget's snapshot in step with the app (iOS
 * `WidgetSnapshotComposer` + `WidgetSnapshotPublisher`). The snapshot is
 * rebuilt when the session changes, written beside the reminder registry in
 * `no_backup/` (never backed up, rebuilt on launch), and the widgets are
 * redrawn only when it actually changed. Nothing about money enters it.
 */
class WidgetCoordinator(
    private val context: Context,
    private val sessions: SessionStore,
    private val scope: CoroutineScope,
    private val nowMs: () -> Double,
) {
    private val mutex = Mutex()
    private var published: String? = null

    @OptIn(FlowPreview::class)
    fun start() {
        scope.launch {
            sessions.session.debounce(500).collectLatest { refresh() }
        }
    }

    /** Recomposes now: launch, foreground, and a clock or time-zone change. */
    suspend fun refresh() = mutex.withLock {
        val snapshot = withContext(Dispatchers.Default) { compose() }
        // Every snapshot starts "now": its first interval's figures and the one-year expiry move with the clock.
        // Only its boundaries, labels, the later intervals and the rows say whether anything changed.
        val content = snapshot.copy(
            generatedAtMs = 0,
            expiresAtMs = 0,
            entries = snapshot.entries.mapIndexed { i, e ->
                if (i == 0) e.copy(dateMs = 0, countdownValueAtDateMs = 0, remainingEffectiveMsAtDateMs = 0, progressAtDate = 0.0) else e
            },
        ).encode()
        if (content == published && file(context).exists()) return@withLock
        withContext(Dispatchers.IO) { write(context, snapshot.encode()) }
        published = content
        WidgetSignals.redraw(context)
    }

    private fun compose(): WidgetSnapshot {
        val session = sessions.session.value
        val now = nowMs().toLong()
        val prefs = session.env.preferences
        // The app's language, not only the system's: before Android 13 an in-app choice lives in Compose alone.
        val tag = AppLocale.tag(AppLanguages.effective(prefs.languageOverride, AppLocale.systemPreferred()))
        val res = context.createConfigurationContext(
            Configuration(context.resources.configuration).apply { setLocales(LocaleList(Locale.forLanguageTag(tag))) },
        ).resources
        val text = TimerText(res, res.configuration.locales[0], DateFormat.is24HourFormat(context), hideEarnings = true)
        val inputs = TimerCoordinator.reminderInputs(res, prefs)
        val upcoming = WidgetUpcoming(
            session,
            events = { shift, at ->
                UpcomingTimeline.events(
                    shift, at, ScheduleRules.reminders(session.rulesInput(at), inputs),
                    microBreakEnabled = prefs.microBreakEnabled,
                    milestonesEnabled = prefs.notificationMode == "milestones",
                )
            },
            words = { event -> timelineWords(event, res, text, session, now.toDouble()).let { (title, detail) -> title to detail.orEmpty() } },
        )
        val future = WidgetSnapshotComposer.futureShifts(session, now)
        return WidgetSnapshotComposer.compose(session, now, tag, future, upcoming)
    }

    companion object {
        fun file(context: Context): File = File(context.noBackupFilesDir, "widget/snapshot.json")

        fun read(context: Context): WidgetSnapshot? =
            runCatching { WidgetSnapshot.decode(file(context).readText()) }.getOrNull()

        private fun write(context: Context, text: String) {
            val target = file(context)
            target.parentFile?.mkdirs()
            val temporary = File(target.parentFile, "snapshot.json.tmp")
            temporary.writeText(text)
            if (!temporary.renameTo(target)) target.writeText(text)
        }
    }
}
