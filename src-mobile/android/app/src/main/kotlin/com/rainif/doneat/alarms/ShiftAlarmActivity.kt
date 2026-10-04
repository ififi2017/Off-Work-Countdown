package com.rainif.doneat.alarms

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Alarm
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.R
import com.rainif.doneat.core.data.ShiftAlarmEntry
import com.rainif.doneat.core.designsystem.DoneAtTheme
import com.rainif.doneat.core.domain.alarms.ShiftAlarmPlanner
import kotlinx.coroutines.launch

/** Shown over the keyguard without dismissing it or exposing the main app's records. */
class ShiftAlarmActivity : ComponentActivity() {
    private var alarmID by mutableStateOf<java.util.UUID?>(null)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (android.os.Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(true); setTurnScreenOn(true) }
        else @Suppress("DEPRECATION") window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        enableEdgeToEdge()
        alarmID = ShiftAlarms.id(intent)
        setContent {
            val registry by ShiftAlarms.sync(this).state.collectAsStateWithLifecycle()
            val entry = registry.entries.firstOrNull { it.alarm.id == alarmID && it.phase == ShiftAlarmEntry.Phase.RINGING }
            LaunchedEffect(entry) { if (entry == null) finish() }
            val scope = rememberCoroutineScope()
            com.rainif.doneat.ui.SystemBarsFollowTheme(isSystemInDarkTheme())
            DoneAtTheme {
                Surface(Modifier.fillMaxSize()) {
                    Column(Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(32.dp),
                        verticalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterVertically), horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Outlined.Alarm, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.primary)
                        Text(stringResource(R.string.shiftAlarmsTitle), style = MaterialTheme.typography.titleMedium)
                        Text(entry?.title.orEmpty(), style = MaterialTheme.typography.headlineLarge, textAlign = TextAlign.Center)
                        Button(onClick = { alarmID?.let { id -> scope.launch { ShiftAlarms.sync(this@ShiftAlarmActivity).stop(id) } } }, modifier = Modifier.fillMaxWidth().heightIn(min = 64.dp)) {
                            Text(stringResource(R.string.shiftAlarmStop))
                        }
                        if (entry?.let { ShiftAlarmPlanner.snoozeAt(System.currentTimeMillis(), it.untilMs) } != null) {
                            OutlinedButton(onClick = { alarmID?.let { id -> scope.launch {
                                if (!ShiftAlarms.sync(this@ShiftAlarmActivity).snooze(id, System.currentTimeMillis())) ShiftAlarms.sync(this@ShiftAlarmActivity).stop(id)
                            } } }, modifier = Modifier.fillMaxWidth().heightIn(min = 64.dp)) { Text(stringResource(R.string.shiftAlarmSnooze)) }
                        }
                    }
                }
            }
        }
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); alarmID = ShiftAlarms.id(intent) }
}
