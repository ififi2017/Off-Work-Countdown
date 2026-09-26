package com.rainif.doneat.ongoing

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.text.format.DateFormat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.rainif.doneat.DoneAtApplication
import com.rainif.doneat.MainActivity
import com.rainif.doneat.R
import com.rainif.doneat.core.data.FocusStore
import com.rainif.doneat.core.data.RecordStore
import com.rainif.doneat.core.data.SessionStore
import com.rainif.doneat.core.data.SettingsRepository
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.session.OngoingDecision
import com.rainif.doneat.core.domain.session.OngoingPlan
import com.rainif.doneat.core.domain.session.OngoingSurface
import com.rainif.doneat.reminders.ReminderNotifier
import com.rainif.doneat.ui.timer.TimerText
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * The quiet countdown notification (iOS's Live Activity, as an ordinary
 * notification; guide §8.3). A running focus or break phase shows while it
 * runs; otherwise the shift shows for its last few minutes. The system ticks
 * the countdown and removes the notification at its end, so nothing runs
 * meanwhile; a non-waking alarm brings the next change (a window opening, a
 * phase ending). Hours and task titles only: never money.
 */
class OngoingCoordinator(
    private val context: Context,
    private val sessions: SessionStore,
    private val records: RecordStore,
    private val settings: SettingsRepository,
    private val focus: FocusStore,
    private val authorized: StateFlow<Boolean>,
    private val scope: CoroutineScope,
    private val nowMs: () -> Double,
) {
    private val mutex = Mutex()
    private var shown: OngoingDecision? = null

    @OptIn(FlowPreview::class)
    fun start() {
        scope.launch {
            combine(sessions.session, records.state, settings.device, authorized, focus.queue) { _, _, _, _, _ -> Unit }
                .debounce(300)
                .collectLatest { apply() }
        }
    }

    /** Shows, updates or clears the notification for this moment, and books the next change. */
    suspend fun apply() = mutex.withLock {
        val now = nowMs()
        val device = settings.device.value
        val state = records.state.value
        val session = sessions.session.value
        val phase = if (device.focusOngoingEnabled && authorized.value) focus.activeSession(state) else null
        // A day with planned focus belongs to focus: no separate clock-off countdown to pre-empt it (iOS).
        val focusPlanned = device.focusOngoingEnabled && authorized.value && focus.queue.value.isNotEmpty()
        val work = if (device.ongoingEnabled && !focusPlanned) OngoingPlan.workWindow(session, now, device.ongoingLeadMinutes) else null
        val decision = OngoingPlan.choose(work, phase, now)
        if (decision == null || !ReminderNotifier.canPost(context)) {
            NotificationManagerCompat.from(context).cancel(TAG, ID)
            shown = null
        } else if (decision != shown || !isShowing()) {
            post(decision, state, now)
            shown = decision
        }
        schedule(OngoingPlan.nextChangeAtMs(work, phase, now))
    }

    private fun isShowing() = context.getSystemService(NotificationManager::class.java).activeNotifications.any { it.tag == TAG && it.id == ID }

    private fun post(decision: OngoingDecision, state: RecordState, now: Double) {
        val res = context.resources
        ensureChannel(context)
        val text = TimerText(res, res.configuration.locales[0], DateFormat.is24HourFormat(context), hideEarnings = true)
        val end = decision.endAtMs
        val (title, body, tab) = when (decision.surface) {
            // Titled with the clock-off time, not "time left": the countdown is the wall clock, and
            // a break inside the window would make "left of today's shift" untrue.
            OngoingSurface.WORK -> Triple("${res.getString(R.string.endTime)} ${text.time(end)}", null, "timer")
            OngoingSurface.FOCUS -> {
                val task = focus.activeSession(state)?.taskID?.let { id -> state.focusTasks.firstOrNull { it.id == id && it.deletedAtMs == null } }
                Triple(task?.title ?: res.getString(R.string.focusTitle), res.getString(R.string.focusTitle), "focus")
            }
            OngoingSurface.SHORT_BREAK -> Triple(res.getString(R.string.focusShortBreak), null, "focus")
            OngoingSurface.LONG_BREAK -> Triple(res.getString(R.string.focusLongBreak), null, "focus")
        }
        val open = PendingIntent.getActivity(
            context, if (tab == "focus") 3 else 2,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(MainActivity.EXTRA_TAB, tab),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_reminder)
            .setContentTitle(title)
            .apply { body?.let(::setContentText) }
            .setWhen(end.toLong())
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            // Gone by itself at the end, whether or not the app runs then.
            .setTimeoutAfter((end - now).toLong().coerceAtLeast(1))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(open)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(TAG, ID, notification)
        } catch (_: SecurityException) {
            // Permission withdrawn between the check and the post: nothing to show.
        }
    }

    private fun alarm() = PendingIntent.getBroadcast(
        context, 0, Intent(context, OngoingReceiver::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** RTC, not a wake-up: a sleeping phone shows nobody a notification, and it fires as the screen comes on. */
    private fun schedule(atMs: Double?) {
        val manager = context.getSystemService(AlarmManager::class.java)
        if (atMs == null) return manager.cancel(alarm())
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
        if (exact) manager.setExact(AlarmManager.RTC, atMs.toLong(), alarm())
        else manager.setWindow(AlarmManager.RTC, atMs.toLong(), 60_000, alarm())
    }

    companion object {
        private const val CHANNEL = "ongoing"
        private const val TAG = "ongoing"
        private const val ID = 1

        /** Low importance: it sits in the shade and on the Lock Screen without a sound or a heads-up. */
        fun ensureChannel(context: Context) {
            val channel = NotificationChannel(CHANNEL, context.getString(R.string.ongoingNotification), NotificationManager.IMPORTANCE_LOW)
                .apply { setShowBadge(false) }
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}

/** The next change in the countdown notification: a window opening, a phase or a shift ending. Not exported. */
class OngoingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val graph = (context.applicationContext as DoneAtApplication).graph
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                // A cold process applies on launch once the archive is read.
                if (graph.loaded.value) graph.ongoing.apply()
            } finally {
                pending.finish()
            }
        }
    }
}
