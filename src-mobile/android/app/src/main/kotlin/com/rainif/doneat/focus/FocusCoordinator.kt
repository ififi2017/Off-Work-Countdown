package com.rainif.doneat.focus

import android.content.Context
import android.content.res.Resources
import android.text.format.DateFormat
import com.rainif.doneat.R
import com.rainif.doneat.core.data.FocusStore
import com.rainif.doneat.core.data.RecordStore
import com.rainif.doneat.core.data.SessionStore
import com.rainif.doneat.core.data.SettingsRepository
import com.rainif.doneat.core.domain.focus.FocusAlertText
import com.rainif.doneat.core.domain.focus.FocusReminders
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.reminders.ReminderPlanner
import com.rainif.doneat.core.domain.schedule.Reminder
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.reminders.Reminders
import com.rainif.doneat.timer.TimerCoordinator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Keeps the system in step with focus (iOS `FocusStore`'s expiry task,
 * scheduled wake and `NotificationService.scheduleFocusTimers`):
 *
 * - the running phase's alerts are registered when it starts, both of them,
 *   since a sleeping phone cannot compose the second when the first fires;
 * - while the app runs, it wakes at the phase's planned end or the next
 *   queued plan start. Launch and foreground reconcile whatever happened
 *   while it did not, so nothing polls in the background.
 */
class FocusCoordinator(
    private val context: Context,
    private val focus: FocusStore,
    private val records: RecordStore,
    private val sessions: SessionStore,
    private val settings: SettingsRepository,
    private val authorized: StateFlow<Boolean>,
    private val scope: CoroutineScope,
    private val nowMs: () -> Double,
) {
    @OptIn(FlowPreview::class)
    fun start() {
        scope.launch {
            combine(records.state, sessions.session, authorized, settings.device, focus.queue) { state, _, _, device, _ -> state to device.focusNotificationsEnabled }
                .debounce(200)
                .collectLatest { (state, notificationsEnabled) ->
                    val now = nowMs()
                    val active = focus.activeSession(state)
                    val alarms = if (active == null || !notificationsEnabled) {
                        emptyList()
                    } else {
                        ReminderPlanner.focusAlarms(active.id, reminders(state).alerts(state, active), now)
                    }
                    Reminders.schedule(context, alarms, ReminderPlanner.FOCUS_PREFIX, TimerCoordinator.channelNames(context.resources))
                    // Then wait for the next thing that happens by itself, and let it happen.
                    val wake = listOfNotNull(active?.plannedEndAtMs, focus.queue.value.firstOrNull()?.startedAtMs).minOrNull() ?: return@collectLatest
                    delay((wake - nowMs()).toLong().coerceAtLeast(0) + 250)
                    val at = nowMs()
                    focus.refreshScheduled(at)
                    focus.finishElapsed(at)
                }
        }
    }

    /** Launch and foreground: settle what happened while away, then line up the rest of the day. */
    suspend fun reconcile() {
        val now = nowMs()
        focus.reconcile(now)
        focus.applyDefaultTemplateIfNeeded(now)
        focus.refreshScheduled(now)
    }

    /** The plan's breaks in place of the fixed health reminders, for the shift being drawn. */
    fun breakTakeover(state: RecordState, microBreakEnabled: Boolean): (List<Reminder>) -> List<Reminder> = { reminders ->
        reminders(state).applyingBreakTakeover(reminders, state, nowMs(), microBreakEnabled)
    }

    private fun reminders(state: RecordState) = FocusReminders(focus.environment(state), focus.planning(state), AlertText(context.resources, context))

    /** Focus alert copy in the app's language; clock times in the device's zone and 12/24-hour setting. */
    private class AlertText(private val res: Resources, context: Context) : FocusAlertText {
        private val locale = res.configuration.locales[0]
        private val time = DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, if (DateFormat.is24HourFormat(context)) "Hm" else "hm"), locale)
        private fun count(value: Int) = NumberFormat.getIntegerInstance(locale).format(value)
        private fun time(ms: Double) = time.format(Instant.ofEpochMilli(ms.toLong()).atZone(ZoneId.systemDefault()))

        override val focusTitle get() = res.getString(R.string.focusTitle)
        override val breakOver get() = res.getString(R.string.focusBreakOver)
        override val dayDone get() = res.getString(R.string.focusActivityDayDone)
        override val endedNaturally get() = res.getString(R.string.focusEndedNaturally)
        override val endedAtBoundary get() = res.getString(R.string.focusEndedAtBoundary)
        override val nextFocus get() = res.getString(R.string.focusNextFocusBody)
        override val breakReminderTitle get() = res.getString(R.string.microBreakReminder)
        override fun pomodoro(index: Int, total: Int) = Strings.focusActivityPomodoro(res, count(index), count(total))
        override fun breakUntil(minutes: Int, endAtMs: Double) = Strings.focusBreakUntil(res, count(minutes), time(endAtMs))
        override fun nextUp(task: String, startAtMs: Long) = Strings.focusActivityNextUp(res, task, time(startAtMs.toDouble()))
        override fun focusBreakBody(minutes: Int) = Strings.focusBreakReminderBody(res, count(minutes))
    }
}
