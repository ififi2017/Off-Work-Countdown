package com.rainif.doneat.alarms

import android.content.Intent
import android.os.Bundle
import androidx.core.content.edit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.foundation.isSystemInDarkTheme
import com.rainif.doneat.DoneAtApplication
import com.rainif.doneat.MainActivity
import com.rainif.doneat.core.designsystem.DoneAtTheme
import com.rainif.doneat.core.designsystem.ThemeMode
import com.rainif.doneat.core.domain.alarms.ShiftAlarmSettings
import com.rainif.doneat.ui.AppLanguageScope
import com.rainif.doneat.ui.settings.ShiftAlarmSettingsScreen
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

/** Seed only the isolated .alarmqa install. Release has neither this activity nor a fake deadline. */
class ShiftAlarmQaActivity : ComponentActivity() {
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); recreate() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!packageName.endsWith(".alarmqa")) { finish(); return }
        enableEdgeToEdge()
        val graph = (application as DoneAtApplication).graph
        lifecycleScope.launch {
            graph.loaded.first { it }
            when (intent.getStringExtra("action")) {
                "prepare" -> {
                    val now = System.currentTimeMillis()
                    val fire = ((now + intent.getIntExtra("delaySeconds", 20) * 1_000L) / 60_000 + 1) * 60_000
                    val start = Instant.ofEpochMilli(fire + 15 * 60_000).atZone(ZoneId.systemDefault())
                    val minute = start.hour * 60 + start.minute
                    val expiry = intent.getIntExtra("expirySeconds", 0).takeIf { it > 0 }?.let { fire + it * 1_000L } ?: 0L
                    withContext(Dispatchers.IO) { getSharedPreferences("debug_plus", MODE_PRIVATE).edit(commit = true) { putLong("alarmExpiry", expiry) } }
                    graph.plus.setDebugAuthorized(true)
                    graph.settings.edit { it.copy(startMinutes = minute, endMinutes = (minute + 60) % 1440,
                        workdays = (0..6).toList(), scheduleMode = "classic", lunchEnabled = false, salaryEnabled = false,
                        recordsTimeZoneIdentifier = ZoneId.systemDefault().id, notificationMode = "off", microBreakEnabled = false,
                        languageOverride = intent.getStringExtra("language") ?: "zh-CN") }
                    if (!graph.settings.device.value.onboardingComplete) graph.settings.completeSetup()
                    graph.settings.updateDevice { it.copy(shiftAlarms = ShiftAlarmSettings(true, 15)) }
                    // Wait for the store's combined environment, not a guessed UI delay.
                    graph.sessions.session.first { it.env.preferences.startMinutes == minute }
                    graph.shiftAlarms.reconcile(true)
                }
                "clear" -> { graph.settings.updateDevice { it.copy(shiftAlarms = ShiftAlarmSettings()) }; ShiftAlarms.sync(this@ShiftAlarmQaActivity).clear() }
            }
        }
        setContent {
            val prefs by graph.settings.preferences.collectAsStateWithLifecycle()
            val dark = when (intent.getStringExtra("theme")) { "dark" -> true; "light" -> false; else -> isSystemInDarkTheme() }
            com.rainif.doneat.ui.SystemBarsFollowTheme(dark)
            AppLanguageScope(prefs.languageOverride) {
                DoneAtTheme(themeMode = when (intent.getStringExtra("theme")) { "dark" -> ThemeMode.DARK; "light" -> ThemeMode.LIGHT; else -> ThemeMode.SYSTEM }) {
                    ShiftAlarmSettingsScreen(graph, { startActivity(Intent(this, MainActivity::class.java).setAction(ShiftAlarms.OPEN).putExtra(MainActivity.EXTRA_TAB, "settings")) }, { finish() })
                }
            }
        }
    }
}
