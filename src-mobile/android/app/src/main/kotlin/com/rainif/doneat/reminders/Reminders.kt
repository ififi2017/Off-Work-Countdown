package com.rainif.doneat.reminders

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.rainif.doneat.MainActivity
import com.rainif.doneat.R
import com.rainif.doneat.core.data.AlarmPort
import com.rainif.doneat.core.data.ReminderSync
import com.rainif.doneat.core.data.ReminderSyncResult
import com.rainif.doneat.core.domain.reminders.AlarmTiming
import com.rainif.doneat.core.domain.reminders.PlannedReminder
import com.rainif.doneat.core.domain.reminders.ReminderChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

/**
 * The app's single entry to reminders. Rules and planning live in the domain;
 * this only holds the system's alarms equal to the plan and posts them.
 *
 * No foreground service, no polling: every reminder is an absolute alarm
 * registered up front, as iOS schedules its notification list.
 */
object Reminders {
    @Volatile private var instance: ReminderSync? = null

    fun sync(context: Context): ReminderSync = instance ?: synchronized(this) {
        instance ?: ReminderSync(
            // Device-local: a restored or transferred device holds none of these alarms.
            context.noBackupFilesDir.toPath().resolve("reminders/registry.json"),
            AndroidAlarms(context.applicationContext),
        ).also { instance = it }
    }

    /**
     * Holds [desired] under [prefix] ([com.rainif.doneat.core.domain.reminders.ReminderPlanner.SHIFT_PREFIX]
     * or `FOCUS_PREFIX`). [channelNames] are the localized channel names;
     * channels are created or renamed here, so one always exists before an alarm can fire.
     */
    suspend fun schedule(context: Context, desired: List<PlannedReminder>, prefix: String, channelNames: Map<ReminderChannel, String>): ReminderSyncResult {
        ReminderNotifier.ensureChannels(context, channelNames)
        return sync(context).sync(desired, prefix)
    }

    fun capability(context: Context) = ReminderCapability(
        notificationsAllowed = ReminderNotifier.canPost(context),
        exactAlarmsAllowed = AndroidAlarms(context).canScheduleExact(),
    )
}

/** What the settings row shows. Neither blocks the app: reminders are an extra. */
data class ReminderCapability(val notificationsAllowed: Boolean, val exactAlarmsAllowed: Boolean) {
    /** Without the exact-alarm grant the system may defer reminders; say so rather than promise the minute. */
    val mayBeLate get() = notificationsAllowed && !exactAlarmsAllowed

    companion object {
        /** The app's notification settings; used after a denial instead of asking again. */
        fun notificationSettings(context: Context) = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)

        /** Where the user grants exact alarms (Android 12+); null where none is needed. */
        fun exactAlarmSettings(context: Context): Intent? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.fromParts("package", context.packageName, null))
            } else {
                null
            }
    }
}

/** [AlarmPort] over AlarmManager. Each alarm is a PendingIntent keyed by the reminder id in its data URI. */
internal class AndroidAlarms(private val context: Context) : AlarmPort {
    private val manager get() = context.getSystemService(AlarmManager::class.java)

    override fun canScheduleExact() = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()

    override fun schedule(reminder: PlannedReminder, timing: AlarmTiming) {
        val operation = pendingIntent(reminder.id, PendingIntent.FLAG_UPDATE_CURRENT)!!
        when (timing) {
            AlarmTiming.EXACT -> try {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, reminder.atMs, operation)
            } catch (_: SecurityException) {
                // The grant was revoked between the check and the call.
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, reminder.atMs, operation)
            }
            AlarmTiming.INEXACT -> manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, reminder.atMs, operation)
            AlarmTiming.WINDOW -> manager.setWindow(AlarmManager.RTC_WAKEUP, reminder.atMs, HEALTH_WINDOW_MS, operation)
        }
    }

    override fun cancel(id: String) {
        pendingIntent(id, PendingIntent.FLAG_NO_CREATE)?.let {
            manager.cancel(it)
            it.cancel()
        }
    }

    private fun pendingIntent(id: String, flag: Int): PendingIntent? = PendingIntent.getBroadcast(
        context, 0,
        Intent(context, ReminderReceiver::class.java).setData(reminderUri(id)),
        flag or PendingIntent.FLAG_IMMUTABLE,
    )

    companion object {
        private const val HEALTH_WINDOW_MS = 10 * 60_000L
        fun reminderUri(id: String): Uri = Uri.Builder().scheme("doneat").authority("reminder").appendPath(id).build()
    }
}

/**
 * Fires a registered alarm. Not exported: only the system's alarm delivery
 * reaches it. It posts only what the registry still holds, so a stale,
 * cancelled or repeated delivery posts nothing and no intent extra is trusted.
 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.data?.takeIf { it.scheme == "doneat" && it.authority == "reminder" }?.lastPathSegment ?: return
        runAsync {
            Reminders.sync(context).take(id, System.currentTimeMillis())?.let { ReminderNotifier.post(context, it) }
        }
    }
}

/**
 * Reboot, app update, clock or zone change, or the exact-alarm grant being
 * given: re-register what is still ahead, never replay what was missed.
 * Wall-clock shifts are recomputed the next time the app runs.
 */
class ReminderSystemEventReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in HANDLED) return
        runAsync { Reminders.sync(context).restore(System.currentTimeMillis()) }
    }

    private companion object {
        val HANDLED = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            // AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED (API 31); older systems never send it.
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED",
        )
    }
}

private fun BroadcastReceiver.runAsync(work: suspend () -> Unit) {
    val pending = goAsync()
    CoroutineScope(Dispatchers.IO).launch {
        try {
            // A receiver has about ten seconds; the registry is a small local file.
            withTimeout(8_000) { work() }
        } finally {
            pending.finish()
        }
    }
}

internal object ReminderNotifier {
    private fun channelID(channel: ReminderChannel) = "reminders.${channel.name.lowercase()}"

    fun canPost(context: Context): Boolean {
        val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        return granted && NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    /** Creates missing channels and renames existing ones; the user's per-channel choices are kept by the system. */
    fun ensureChannels(context: Context, names: Map<ReminderChannel, String>) {
        val manager = context.getSystemService(NotificationManager::class.java)
        for ((channel, name) in names) {
            val importance = if (channel == ReminderChannel.HEALTH) NotificationManager.IMPORTANCE_DEFAULT else NotificationManager.IMPORTANCE_HIGH
            manager.createNotificationChannel(NotificationChannel(channelID(channel), name, importance))
        }
    }

    fun post(context: Context, reminder: PlannedReminder) {
        // Denied notifications leave the app fully usable; the reminder is simply not shown.
        if (!canPost(context)) return
        // Focus alerts open the Focus tab; their own request code keeps the two intents apart.
        val focus = reminder.channel == ReminderChannel.FOCUS
        val open = PendingIntent.getActivity(
            context, if (focus) 1 else 0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .apply { if (focus) putExtra(MainActivity.EXTRA_TAB, "focus") },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, channelID(reminder.channel))
            .setSmallIcon(R.drawable.ic_stat_reminder)
            .setContentTitle(reminder.title)
            .setContentText(reminder.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(reminder.body))
            .setCategory(if (reminder.channel == ReminderChannel.FOCUS) NotificationCompat.CATEGORY_ALARM else NotificationCompat.CATEGORY_REMINDER)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try {
            // Tagged by id: a repeated post replaces rather than stacks.
            NotificationManagerCompat.from(context).notify(reminder.id, 0, notification)
        } catch (_: SecurityException) {
            // Permission withdrawn between the check and the post.
        }
    }
}
