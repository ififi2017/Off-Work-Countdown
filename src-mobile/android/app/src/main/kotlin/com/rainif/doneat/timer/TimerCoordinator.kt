package com.rainif.doneat.timer

import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.os.LocaleList
import com.rainif.doneat.R
import com.rainif.doneat.core.data.SessionStore
import com.rainif.doneat.core.data.SettingsRepository
import com.rainif.doneat.core.domain.records.SyncedPreferences
import com.rainif.doneat.core.domain.reminders.ReminderChannel
import com.rainif.doneat.core.domain.reminders.ReminderPlanner
import com.rainif.doneat.core.domain.schedule.Reminder
import com.rainif.doneat.core.domain.schedule.ReminderInputs
import com.rainif.doneat.core.domain.session.ShiftReminderPlan
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.reminders.Reminders
import com.rainif.doneat.ui.AppLocale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import java.util.Locale

/**
 * Keeps what the system holds in step with the session: the shift alarms
 * whenever the session or its settings change, and the one-time arming when
 * setup completes. Housekeeping ([reconcile]) runs on launch, on resume and
 * at the timer's own boundaries; nothing polls in the background.
 */
class TimerCoordinator(
    private val context: Context,
    private val sessions: SessionStore,
    private val settings: SettingsRepository,
    private val scope: CoroutineScope,
    private val nowMs: () -> Double,
    /** Changes that can move a reminder besides the session, such as today's focus plan. */
    private val planChanges: Flow<Any?> = flowOf(Unit),
    /** A plan taking over the break reminders; identity when there is none. */
    private val adjust: (SyncedPreferences) -> (List<Reminder>) -> List<Reminder> = { { it } },
) {
    @OptIn(FlowPreview::class)
    fun start() {
        scope.launch {
            // Settings edits come in bursts (a time picker, a switch); schedule once they settle.
            combine(sessions.session, planChanges) { session, _ -> session }.debounce(300).collectLatest { session ->
                val now = nowMs()
                val res = localizedResources(session.env.preferences.languageOverride)
                val alarms = ShiftReminderPlan.alarms(session, now, reminderInputs(res, session.env.preferences), adjust(session.env.preferences))
                Reminders.schedule(context, alarms, ReminderPlanner.SHIFT_PREFIX, channelNames(res))
            }
        }
        scope.launch {
            // Only the transition: a device that was already set up is armed by `SessionStore.load`.
            settings.isSetUp.drop(1).filter { it }.collectLatest {
                val now = nowMs()
                sessions.run(now) { finishSetup(it, now) }
            }
        }
    }

    /**
     * Notifications speak the app's language. Android 13+ already gives the
     * application that locale; earlier versions need a configured context.
     */
    private fun localizedResources(override: String?): Resources {
        if (override == null || AppLocale.hasPerAppLanguage) return context.resources
        val configuration = Configuration(context.resources.configuration).apply {
            setLocales(LocaleList(Locale.forLanguageTag(AppLocale.tag(override))))
        }
        return context.createConfigurationContext(configuration).resources
    }

    suspend fun reconcile() {
        val now = nowMs()
        sessions.run(now) { reconcile(it, now) }
    }

    companion object {
        fun channelNames(res: Resources) = mapOf(
            ReminderChannel.SHIFT to res.getString(R.string.shiftReminders),
            ReminderChannel.HEALTH to res.getString(R.string.microBreakReminder),
            ReminderChannel.FOCUS to res.getString(R.string.focusTitle),
        )

        /** iOS `ShiftSessionStore.reminderInputs`, in the app's language. The cycle summary needs Plus (T20). */
        fun reminderInputs(res: Resources, p: SyncedPreferences) = ReminderInputs(
            mode = p.notificationMode,
            fallbackTitle = res.getString(R.string.offWorkReminder),
            breakTitle = res.getString(R.string.breakReminder),
            milestoneTitles = mapOf(
                50 to Strings.notificationMilestoneTitle(res, "50"),
                75 to Strings.notificationMilestoneTitle(res, "25"),
                90 to Strings.notificationMilestoneTitle(res, "10"),
                95 to Strings.notificationMilestoneTitle(res, "5"),
                100 to res.getString(R.string.offWorkTime),
            ),
            milestoneMessages = mapOf(
                50 to listOf(res.getString(R.string.notificationMilestone50)),
                75 to listOf(res.getString(R.string.notificationMilestone75)),
                90 to listOf(res.getString(R.string.notificationMilestone90)),
                95 to listOf(res.getString(R.string.notificationMilestone95)),
                100 to listOf(res.getString(R.string.offWorkTime)),
            ),
            lunchStartEnabled = p.lunchStartReminderEnabled,
            lunchStartBody = res.getString(R.string.lunchStartNotification),
            lunchEndEnabled = p.lunchEndReminderEnabled,
            lunchEndBody = res.getString(R.string.lunchEndNotification),
            microBreakEnabled = p.microBreakEnabled,
            microBreakTitle = res.getString(R.string.microBreakReminder),
            microBreakIntervalMinutes = p.microBreakIntervalMinutes,
            microBreakMessages = res.getStringArray(R.array.microBreakMessages).toList(),
            cycleEndSummaryBody = null,
        )
    }
}
