package com.rainif.doneat.alarms

import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.*
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.rainif.doneat.R
import kotlinx.coroutines.*
import java.lang.ref.WeakReference
import java.util.UUID

/** Alarm audio only. No full-screen intent, window flags, Activity launch, display wake, or keyguard changes. */
class ShiftAlarmRingingService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var watch: Job? = null
    private var player: MediaPlayer? = null
    private var vibration: Vibrator? = null
    private var id: UUID? = null
    private var token: String? = null
    private var generation = 0
    override fun onBind(intent: Intent?) = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nextID = intent?.getStringExtra("id")?.let { runCatching { UUID.fromString(it) }.getOrNull() }
            ?: run { stopSelf(); return START_NOT_STICKY }
        val nextToken = intent.getStringExtra(AndroidShiftAlarmPlatform.EXTRA_TOKEN)
            ?: run { stopSelf(); return START_NOT_STICKY }
        val coordinator = ShiftAlarmCoordinator.current ?: run { stopSelf(); return START_NOT_STICKY }
        val alarm = coordinator.currentRinging(nextID, nextToken) ?: run { stopSelf(); return START_NOT_STICKY }
        id?.let { previous -> if (previous != nextID) token?.let { coordinator.stop(previous, it) } }
        releaseAudio()
        id = nextID
        token = nextToken
        generation = startId
        active = WeakReference(this)
        AndroidShiftAlarmPlatform.ensureChannel(this)
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, ShiftAlarmRingActivity::class.java).putExtra("id", nextID.toString())
                .putExtra(AndroidShiftAlarmPlatform.EXTRA_TOKEN, nextToken), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun action(name: String) = PendingIntent.getBroadcast(this, 0,
            Intent(this, ShiftAlarmReceiver::class.java).setAction(name)
                .setData(android.net.Uri.parse("doneat-shift-alarm://ring/$nextID"))
                .putExtra(AndroidShiftAlarmPlatform.EXTRA_TOKEN, nextToken), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val res = coordinator.resources()
        val notification = NotificationCompat.Builder(this, AndroidShiftAlarmPlatform.CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_reminder).setContentTitle(alarm.title)
            .setContentText(res.getString(R.string.shiftAlarmsTitle)).setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_HIGH).setOngoing(true).setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC).setContentIntent(open)
            .addAction(0, res.getString(R.string.shiftAlarmStop), action(ShiftAlarmReceiver.ACTION_STOP))
            .addAction(0, res.getString(R.string.shiftAlarmSnooze), action(ShiftAlarmReceiver.ACTION_SNOOZE)).build()
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification,
                if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK else 0)
        } catch (_: Exception) {
            coordinator.stop(nextID, nextToken)
            stopSelfResult(startId)
            return START_NOT_STICKY
        }
        playAlarm()
        watch?.cancel()
        watch = scope.launch {
            while (isActive) {
                if (coordinator.currentRinging(nextID, nextToken) == null) {
                    coordinator.stop(nextID, nextToken)
                    stopSelf()
                    break
                }
                delay(minOf(1_000, coordinator.ringingRemainingMs() ?: 1_000).coerceAtLeast(1))
            }
        }
        return START_NOT_STICKY
    }

    private fun playAlarm() {
        val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        if (uri != null) {
            val audio = MediaPlayer()
            player = audio
            try {
                audio.setAudioAttributes(attributes)
                // A partial CPU wake lock keeps alarm audio running without turning on the display.
                audio.setWakeMode(this, PowerManager.PARTIAL_WAKE_LOCK)
                audio.setDataSource(this, uri)
                audio.isLooping = true
                audio.setOnPreparedListener { prepared ->
                    if (player === prepared) {
                        val alarmID = id
                        val registrationToken = token
                        if (alarmID != null && registrationToken != null &&
                            ShiftAlarmCoordinator.current?.currentRinging(alarmID, registrationToken) != null) prepared.start()
                        else { releaseAudio(); stopSelfResult(generation) }
                    }
                }
                audio.setOnErrorListener { media, _, _ -> if (player === media) { player = null; media.release() }; true }
                audio.prepareAsync()
            } catch (_: Exception) { audio.release(); player = null }
        }
        vibration = if (Build.VERSION.SDK_INT >= 31) getSystemService(VibratorManager::class.java).defaultVibrator
            else @Suppress("DEPRECATION") (getSystemService(VIBRATOR_SERVICE) as Vibrator)
        if (vibration?.hasVibrator() == true) vibration?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 700, 400), 0), attributes)
    }
    private fun releaseAudio() { player?.release(); player = null; vibration?.cancel(); vibration = null }
    override fun onDestroy() {
        watch?.cancel(); scope.cancel(); releaseAudio()
        if (active?.get() === this) active = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
    companion object {
        private const val NOTIFICATION_ID = 32120
        private var active: WeakReference<ShiftAlarmRingingService>? = null
        internal fun stopIfRinging(id: UUID, token: String) {
            Handler(Looper.getMainLooper()).post {
                active?.get()?.let { service -> if (service.id == id && service.token == token) service.stopSelfResult(service.generation) }
            }
        }
    }
}
