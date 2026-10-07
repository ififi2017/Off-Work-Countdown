package com.rainif.doneat.alarms

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.rainif.doneat.MainActivity
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.alarms.ShiftAlarmAuthorization
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.UUID

/** Non-exported. A schedule id alone never suffices: the coordinator checks its confirmed random token. */
class ShiftAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val coordinator = ShiftAlarmCoordinator.current ?: return
        if (intent.action == AndroidShiftAlarmPlatform.ACTION_REFRESH) {
            if (coordinator.settings.value.enabled && coordinator.authorization() != ShiftAlarmAuthorization.Unavailable &&
                NotificationManagerCompat.from(context).areNotificationsEnabled()) postRefresh(context)
            return
        }
        val id = intent.data?.lastPathSegment?.let { runCatching { UUID.fromString(it) }.getOrNull() } ?: return
        val token = intent.getStringExtra(AndroidShiftAlarmPlatform.EXTRA_TOKEN) ?: return
        if (intent.action !in setOf(ACTION_STOP, ACTION_SNOOZE, AndroidShiftAlarmPlatform.ACTION_RING)) return
        val pending = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            try {
                when (intent.action) {
                    ACTION_STOP -> coordinator.stopAndReconcile(id, token)
                    ACTION_SNOOZE -> coordinator.snoozeAndReconcile(id, token)
                    AndroidShiftAlarmPlatform.ACTION_RING -> coordinator.deliver(id, token)
                }
            } finally { pending.finish() }
        }
    }

    private fun postRefresh(context: Context) {
        val res = ShiftAlarmCoordinator.current?.resources() ?: context.resources
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(AndroidShiftAlarmPlatform.REFRESH_CHANNEL,
            res.getString(R.string.shiftAlarmRefreshTitle), NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(context, 20,
            Intent(context, MainActivity::class.java).putExtra("doneat.shiftAlarmSettings", true),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, AndroidShiftAlarmPlatform.REFRESH_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_reminder).setContentTitle(res.getString(R.string.shiftAlarmRefreshTitle))
            .setContentText(res.getString(R.string.shiftAlarmRefreshBody)).setContentIntent(open).setAutoCancel(true).build()
        try { NotificationManagerCompat.from(context).notify("shift-alarm-refresh", 1, notification) } catch (_: SecurityException) { }
    }

    companion object {
        const val ACTION_STOP = "com.rainif.doneat.alarm.STOP"
        const val ACTION_SNOOZE = "com.rainif.doneat.alarm.SNOOZE"
    }
}

/** System events rebuild only the user's enabled alarms. Boot never starts audio or a ringing service. */
class ShiftAlarmSystemEventReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_LOCALE_CHANGED,
                AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)) return
        val coordinator = ShiftAlarmCoordinator.current ?: return
        val pending = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            try { coordinator.onSystemEvent(intent.action == Intent.ACTION_BOOT_COMPLETED ||
                intent.action == AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED) }
            finally { pending.finish() }
        }
    }
}
