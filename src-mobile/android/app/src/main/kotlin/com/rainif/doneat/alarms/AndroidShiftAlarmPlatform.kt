package com.rainif.doneat.alarms

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.AtomicFile
import androidx.core.app.NotificationManagerCompat
import com.rainif.doneat.MainActivity
import com.rainif.doneat.R
import com.rainif.doneat.core.domain.alarms.PlannedShiftAlarm
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** Only shift-alarms' distinct URI namespace is touched. A ledger entry is confirmed after setAlarmClock succeeds. */
internal class AndroidShiftAlarmPlatform(private val context: Context) : ShiftAlarmPlatform {
    private val manager = context.getSystemService(AlarmManager::class.java)
    private val ledger = AtomicFile(File(context.noBackupFilesDir, "shift-alarms/registrations.json"))
    private val commits = VerifiedAlarmLedgerCommit(
        write = { bytes ->
            ledger.baseFile.parentFile?.mkdirs()
            val stream = ledger.startWrite()
            try {
                stream.write(bytes)
                // AtomicFile logs some fsync/rename failures rather than throwing; verify both durability and bytes.
                stream.fd.sync()
                ledger.finishWrite(stream)
            } catch (error: Exception) { ledger.failWrite(stream); throw error }
        },
        read = { ledger.openRead().use { it.readBytes() } },
    )
    private var ledgerUsable = true
    private var held = read()

    override fun exactAllowed() = ledgerUsable && (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms())
    override fun notificationsAllowed(): Boolean {
        ensureChannel(context)
        val notificationManager = context.getSystemService(NotificationManager::class.java)
        return NotificationManagerCompat.from(context).areNotificationsEnabled() &&
            notificationManager.getNotificationChannel(CHANNEL).importance != NotificationManager.IMPORTANCE_NONE
    }
    @Synchronized override fun registrations() = held.toList()

    @Synchronized override fun schedule(registration: AlarmRegistration): AlarmScheduleOutcome {
        if (!exactAllowed() || !notificationsAllowed()) return AlarmScheduleOutcome.FAILED
        // Persist the identity first: a process death during registration must not leave an unowned system alarm.
        val pending = registration.copy(accepted = false)
        val previous = held
        return commitShiftAlarmRegistration(
            persistPending = {
                held = held.filterNot { it.alarm.id == registration.alarm.id } + pending
                write().also { if (!it) held = previous }
            },
            register = {
                val operation = delivery(registration, PendingIntent.FLAG_UPDATE_CURRENT)!!
                val open = PendingIntent.getActivity(context, 0,
                    Intent(context, MainActivity::class.java).setData(Uri.parse("doneat-shift-alarm://settings"))
                        .putExtra("doneat.shiftAlarmSettings", true), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                manager.setAlarmClock(AlarmManager.AlarmClockInfo(registration.scheduledAtMs, open), operation)
            },
            persistAccepted = {
                held = held.map { if (it.alarm.id == registration.alarm.id) pending.copy(accepted = true) else it }
                write()
            },
            rollback = { cancel(registration.alarm.id) },
        )
    }

    @Synchronized override fun markRinging(registration: AlarmRegistration): Boolean {
        val previous = held
        held = held.map { if (it.alarm.id == registration.alarm.id && it.token == registration.token) registration else it }
        if (write()) return true
        held = previous
        cancel(registration.alarm.id)
        return false
    }

    @Synchronized override fun cancel(id: UUID) {
        val canceled = held.firstOrNull { it.alarm.id == id }
        canceled?.let { delivery(it, PendingIntent.FLAG_NO_CREATE)?.let { operation ->
            manager.cancel(operation)
            operation.cancel()
        } }
        held = held.filterNot { it.alarm.id == id }
        write()
        canceled?.let { ShiftAlarmRingingService.stopIfRinging(id, it.token) }
    }

    @Synchronized override fun invalidateRegistrations() {
        // Android drops alarms at reboot and when exact permission is revoked. Preserve their identities for replacement, without claiming acceptance.
        held = held.map { it.copy(accepted = false, ringing = false) }
        write()
    }

    override fun refreshReminder(atMs: Long?, title: String, body: String): Boolean {
        val operation = PendingIntent.getBroadcast(context, 0,
            Intent(context, ShiftAlarmReceiver::class.java).setAction(ACTION_REFRESH).setData(Uri.parse("doneat-shift-alarm://refresh"))
                .putExtra("title", title).putExtra("body", body), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.cancel(operation)
        if (atMs == null || !NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        return try {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, operation)
            true
        } catch (_: Exception) { false }
    }

    private fun delivery(item: AlarmRegistration, flag: Int): PendingIntent? = PendingIntent.getBroadcast(context, 0,
        Intent(context, ShiftAlarmReceiver::class.java).setAction(ACTION_RING)
            .setData(Uri.parse("doneat-shift-alarm://ring/${item.alarm.id}"))
            .putExtra(EXTRA_TOKEN, item.token), flag or PendingIntent.FLAG_IMMUTABLE)

    private fun read(): List<AlarmRegistration> = runCatching {
        val array = JSONArray(ledger.openRead().bufferedReader().use { it.readText() })
        (0 until array.length()).map { index ->
            val json = array.getJSONObject(index)
            val alarm = PlannedShiftAlarm(UUID.fromString(json.getString("id")), json.getLong("fire"), json.getLong("start"),
                json.getString("day"), json.optString("type").takeIf { it.isNotBlank() }?.let(UUID::fromString),
                json.optString("name").takeIf { it.isNotBlank() })
            AlarmRegistration(alarm, json.getString("title"), json.getLong("scheduled"), json.getString("token"),
                json.getBoolean("accepted") && !json.optBoolean("ringing"), false, json.optBoolean("snoozed"))
        }.distinctBy { it.alarm.id }
    }.getOrElse {
        if (ledger.baseFile.exists() || File(ledger.baseFile.path + ".bak").exists()) ledgerUsable = false
        emptyList()
    }

    private fun write(): Boolean = try {
        ledger.baseFile.parentFile?.mkdirs()
        val array = JSONArray()
        held.forEach { item -> array.put(JSONObject().put("id", item.alarm.id.toString()).put("fire", item.alarm.fireAtMs)
            .put("start", item.alarm.shiftStartAtMs).put("day", item.alarm.dayKey).put("type", item.alarm.shiftTypeID?.toString().orEmpty())
            .put("name", item.alarm.shiftName.orEmpty()).put("title", item.title).put("scheduled", item.scheduledAtMs)
            .put("token", item.token).put("accepted", item.accepted).put("ringing", item.ringing).put("snoozed", item.snoozed)) }
        commits.save(array.toString().toByteArray(Charsets.UTF_8)).also { if (!it) ledgerUsable = false }
    } catch (_: Exception) { ledgerUsable = false; false }

    companion object {
        const val CHANNEL = "shift-alarms"
        const val REFRESH_CHANNEL = "shift-alarm-refresh"
        const val ACTION_RING = "com.rainif.doneat.alarm.RING"
        const val ACTION_REFRESH = "com.rainif.doneat.alarm.REFRESH"
        const val EXTRA_TOKEN = "registrationToken"
        fun ensureChannel(context: Context) {
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL, context.getString(R.string.shiftAlarmsTitle), NotificationManager.IMPORTANCE_HIGH)
                    .apply { setSound(null, null); enableVibration(false); setShowBadge(false) })
        }
    }
}
