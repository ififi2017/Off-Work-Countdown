package com.rainif.doneat.alarms

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Alarm
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.rainif.doneat.ui.AppLanguageScope
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.*
import kotlinx.coroutines.delay
import java.util.UUID

/** Opened only when someone taps the notification. Back leaves the alarm under its notification controls. */
class ShiftAlarmRingActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val id = intent.getStringExtra("id")?.let { runCatching { UUID.fromString(it) }.getOrNull() }
        val token = intent.getStringExtra(AndroidShiftAlarmPlatform.EXTRA_TOKEN)
        val coordinator = ShiftAlarmCoordinator.current
        if (id == null || token == null || coordinator?.currentRinging(id, token) == null) { finish(); return }
        setContent { AppLanguageScope(coordinator.languageOverride()) { DoneAtTheme {
            var alarm by remember { mutableStateOf(coordinator.currentRinging(id, token)) }
            LaunchedEffect(Unit) { while (true) {
                alarm = coordinator.currentRinging(id, token)
                if (alarm == null) { finish(); break }
                delay(1_000)
            } }
            Surface(Modifier.fillMaxSize()) {
                Column(Modifier.safeDrawingPadding().padding(DoneAtSpacing.page),
                    verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l, Alignment.CenterVertically),
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Outlined.Alarm, null, Modifier.size(DoneAtSpacing.xxl * 2), tint = MaterialTheme.colorScheme.primary)
                    Text(alarm?.title.orEmpty(), style = MaterialTheme.typography.headlineMedium)
                    DoneAtPrimaryButton(stringResource(R.string.shiftAlarmStop), {
                        coordinator.stop(id, token); finish()
                    }, Modifier.fillMaxWidth())
                    OutlinedButton(onClick = { coordinator.snooze(id, token); finish() }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.shiftAlarmSnooze))
                    }
                }
            }
        } } }
    }
}
