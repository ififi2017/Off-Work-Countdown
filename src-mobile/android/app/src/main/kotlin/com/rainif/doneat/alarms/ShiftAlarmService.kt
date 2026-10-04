package com.rainif.doneat.alarms

import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.rainif.doneat.R
import com.rainif.doneat.core.data.ShiftAlarmEntry
import com.rainif.doneat.core.data.ShiftAlarmSync
import com.rainif.doneat.core.domain.alarms.ShiftAlarmPlanner
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collectLatest
import java.util.UUID

/** Exists only while an accepted alarm is ringing; no polling, network, or background player. */
class ShiftAlarmService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var player: MediaPlayer? = null
    private var wake: PowerManager.WakeLock? = null
    private var focus: AudioFocusRequest? = null
    private var watching: Job? = null
    private var active: UUID? = null

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = ShiftAlarms.id(intent)
        val entry = ShiftAlarms.sync(this).state.value.entries.firstOrNull {
            it.alarm.id == id && it.phase == ShiftAlarmEntry.Phase.RINGING && it.untilMs > System.currentTimeMillis()
        }
        if (entry == null || !ShiftAlarms.permitted(this)) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        ShiftAlarms.channels(this)
        val screen = PendingIntent.getActivity(this, 0, Intent(this, ShiftAlarmActivity::class.java)
            .setData(intent?.data).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, ShiftAlarms.CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_reminder).setContentTitle(entry.title)
            .setCategory(NotificationCompat.CATEGORY_ALARM).setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC).setOngoing(true).setAutoCancel(false)
            .setContentIntent(screen).addAction(0, getString(R.string.shiftAlarmStop), ShiftAlarms.pending(this, ShiftAlarms.STOP, id))
            .apply {
                if (ShiftAlarmPlanner.snoozeAt(System.currentTimeMillis(), entry.untilMs) != null)
                    addAction(0, getString(R.string.shiftAlarmSnooze), ShiftAlarms.pending(this@ShiftAlarmService, ShiftAlarms.SNOOZE, id))
                if (ShiftAlarms.fullScreenAllowed(this@ShiftAlarmService)) setFullScreenIntent(screen, true)
            }.build()
        ServiceCompat.startForeground(this, ShiftAlarms.RING_NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        if (active == id) return START_NOT_STICKY
        val previous = active
        watching?.cancel()
        releaseSound()
        active = id
        if (previous != null) ShiftAlarms.scope.launch { ShiftAlarms.sync(this@ShiftAlarmService).stop(previous) }
        wake = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:shift-alarm").apply {
            acquire(ShiftAlarmSync.RING_TIMEOUT_MS + 5_000)
        }
        play()
        watching = scope.launch {
            ShiftAlarms.sync(this@ShiftAlarmService).state.collectLatest { registry ->
                val current = registry.entries.firstOrNull { it.alarm.id == id && it.phase == ShiftAlarmEntry.Phase.RINGING }
                if (current == null) { finishRinging(); return@collectLatest }
                val end = minOf(current.untilMs, (current.ringingSinceMs ?: System.currentTimeMillis()) + ShiftAlarmSync.RING_TIMEOUT_MS)
                delay((end - System.currentTimeMillis()).coerceAtLeast(0))
                withContext(Dispatchers.IO) { ShiftAlarms.sync(this@ShiftAlarmService).stop(current.alarm.id) }
                finishRinging()
            }
        }
        return START_NOT_STICKY
    }

    private fun play() {
        val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        val audio = getSystemService(AudioManager::class.java)
        focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attributes)
            .setOnAudioFocusChangeListener { change ->
                when (change) {
                    AudioManager.AUDIOFOCUS_GAIN -> runCatching { player?.start() }
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> runCatching { player?.pause() }
                    AudioManager.AUDIOFOCUS_LOSS -> active?.let { id -> ShiftAlarms.scope.launch { ShiftAlarms.sync(this@ShiftAlarmService).stop(id) } }
                }
            }.build()
        val granted = audio.requestAudioFocus(focus!!) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        // Follow the user's alarm volume and Do Not Disturb policy; never change either setting.
        runCatching {
            player = MediaPlayer().apply {
                setAudioAttributes(attributes)
                setDataSource(this@ShiftAlarmService, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
                isLooping = true
                prepare()
                if (granted) start()
            }
        }.onFailure { player?.release(); player = null }
    }

    private fun finishRinging() {
        releaseSound()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
    private fun releaseSound() {
        player?.release(); player = null
        focus?.let { getSystemService(AudioManager::class.java).abandonAudioFocusRequest(it) }; focus = null
        wake?.let { if (it.isHeld) it.release() }; wake = null
    }
    override fun onDestroy() {
        scope.cancel()
        releaseSound()
        super.onDestroy()
    }
}
