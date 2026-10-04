package com.rainif.doneat.alarms

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import com.rainif.doneat.MainActivity
import com.rainif.doneat.R
import com.rainif.doneat.core.data.ShiftAlarmEntry
import com.rainif.doneat.core.data.ShiftAlarmPort
import com.rainif.doneat.core.data.ShiftAlarmSync
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.UUID

/** Only the alarm journal is available before unlock. Records and purchases remain credential protected. */
object ShiftAlarms {
    const val CHANNEL = "shift-wake-alarms"
    const val REFRESH_CHANNEL = "shift-alarm-refresh"
    const val RING_NOTIFICATION = 7201
    const val REFRESH_NOTIFICATION = 7202
    const val OPEN = "com.rainif.doneat.SHIFT_ALARMS"
    const val FIRE = "com.rainif.doneat.SHIFT_ALARM_FIRE"
    const val STOP = "com.rainif.doneat.SHIFT_ALARM_STOP"
    const val SNOOZE = "com.rainif.doneat.SHIFT_ALARM_SNOOZE"
    const val REFRESH = "com.rainif.doneat.SHIFT_ALARM_REFRESH"
    private var instance: ShiftAlarmSync? = null
    internal val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Synchronized fun sync(context: Context): ShiftAlarmSync = instance ?: run {
        val app = context.applicationContext
        val protected = app.createDeviceProtectedStorageContext()
        ShiftAlarmSync(protected.noBackupFilesDir.toPath().resolve("shift-alarms.json"), AndroidShiftAlarmPort(app))
            .also { instance = it }
    }

    fun channels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, context.getString(R.string.shiftAlarmsTitle), NotificationManager.IMPORTANCE_HIGH).apply {
            // The bounded foreground service plays the alarm stream, not a one-shot notification sound.
            setSound(null, null)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        })
        manager.createNotificationChannel(NotificationChannel(REFRESH_CHANNEL, context.getString(R.string.shiftAlarmRefreshTitle), NotificationManager.IMPORTANCE_DEFAULT))
    }

    fun exactAllowed(context: Context) = Build.VERSION.SDK_INT < 31 || context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
    fun notificationsAllowed(context: Context): Boolean =
        (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            context.getSystemService(NotificationManager::class.java).areNotificationsEnabled() &&
            context.getSystemService(NotificationManager::class.java).getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
    fun fullScreenAllowed(context: Context) = Build.VERSION.SDK_INT < 34 || context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
    fun permitted(context: Context) = exactAllowed(context) && notificationsAllowed(context)

    fun openIntent(context: Context): PendingIntent = PendingIntent.getActivity(context, 7200,
        Intent(context, MainActivity::class.java).setAction(OPEN).putExtra(MainActivity.EXTRA_TAB, "settings")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    internal fun pending(context: Context, action: String, id: UUID? = null): PendingIntent = PendingIntent.getBroadcast(context, 0,
        Intent(context, ShiftAlarmReceiver::class.java).setAction(action).setData("doneat-alarm://${context.packageName}/${id ?: "refresh"}".toUri()),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    internal fun id(intent: Intent?): UUID? = runCatching { UUID.fromString(intent?.data?.lastPathSegment) }.getOrNull()
}

private class AndroidShiftAlarmPort(private val context: Context) : ShiftAlarmPort {
    private val manager get() = context.getSystemService(AlarmManager::class.java)
    override fun permitted() = ShiftAlarms.permitted(context)
    override fun schedule(entry: ShiftAlarmEntry) {
        check(permitted())
        manager.setAlarmClock(AlarmManager.AlarmClockInfo(entry.alarm.fireAtMs, ShiftAlarms.openIntent(context)),
            ShiftAlarms.pending(context, ShiftAlarms.FIRE, entry.alarm.id))
    }
    override fun cancel(id: UUID) { manager.cancel(ShiftAlarms.pending(context, ShiftAlarms.FIRE, id)) }
    override fun scheduleRefresh(atMs: Long) {
        check(permitted())
        manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, ShiftAlarms.pending(context, ShiftAlarms.REFRESH))
    }
    override fun cancelRefresh() {
        manager.cancel(ShiftAlarms.pending(context, ShiftAlarms.REFRESH))
        context.getSystemService(NotificationManager::class.java).cancel(ShiftAlarms.REFRESH_NOTIFICATION)
    }
}

/** Non-exported, immutable PendingIntents carry an ID only. The journal owns all delivery data. */
class ShiftAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val result = goAsync()
        ShiftAlarms.scope.launch {
            try {
                val sync = ShiftAlarms.sync(context)
                val id = ShiftAlarms.id(intent)
                when (intent.action) {
                    ShiftAlarms.FIRE -> if (id != null && sync.take(id, System.currentTimeMillis()) != null) {
                        runCatching {
                            ContextCompat.startForegroundService(context, Intent(context, ShiftAlarmService::class.java).setData(intent.data))
                        }.onFailure { sync.stop(id) }
                    }
                    ShiftAlarms.STOP -> if (id != null) sync.stop(id)
                    ShiftAlarms.SNOOZE -> if (id != null && !sync.snooze(id, System.currentTimeMillis())) sync.stop(id)
                    ShiftAlarms.REFRESH -> if (sync.takeRefresh(System.currentTimeMillis()) && ShiftAlarms.notificationsAllowed(context)) {
                        ShiftAlarms.channels(context)
                        context.getSystemService(NotificationManager::class.java).notify(ShiftAlarms.REFRESH_NOTIFICATION,
                            NotificationCompat.Builder(context, ShiftAlarms.REFRESH_CHANNEL)
                                .setSmallIcon(R.drawable.ic_stat_reminder).setContentTitle(context.getString(R.string.shiftAlarmRefreshTitle))
                                .setContentText(context.getString(R.string.shiftAlarmRefreshBody)).setAutoCancel(true)
                                .setContentIntent(ShiftAlarms.openIntent(context)).build())
                    }
                }
            } finally { result.finish() }
        }
    }
}

/** Re-arm absolute future times only. A boot receiver never starts media playback. */
class ShiftAlarmSystemReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_LOCKED_BOOT_COMPLETED, Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED,
                AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)) return
        val result = goAsync()
        ShiftAlarms.scope.launch {
            try { ShiftAlarms.sync(context).restore(System.currentTimeMillis(), afterReboot = intent.action == Intent.ACTION_LOCKED_BOOT_COMPLETED) }
            finally { result.finish() }
        }
    }
}
