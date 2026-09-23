package com.rainif.doneat.ui.timer

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.ui.onboarding.showTimePicker
import java.time.Instant
import java.time.ZoneId

/**
 * Sets or moves the overtime end (iOS `OvertimeSheet`). It can be no earlier
 * than the planned clock-off or now, and has no minimum length: after a
 * clock-off it records time already worked. The rate stays the planned one.
 */
@Composable
fun OvertimeDialog(session: ShiftSession, text: TimerText, dark: Boolean, onDismiss: () -> Unit, onConfirm: (Double) -> Unit) {
    val context = LocalContext.current
    val minimum = remember {
        val now = System.currentTimeMillis().toDouble()
        maxOf(session.snapshot(now)?.plannedEndAtMs ?: now, now)
    }
    var endAtMs by remember { mutableDoubleStateOf(maxOf(minimum, session.state.overtimeEndAtMs ?: minimum)) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.overtimeTitle)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
                Text(stringResource(R.string.overtimeDescription), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.overtimeEndTime), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                    FilledTonalButton(onClick = {
                        showTimePicker(context, dark, ShiftSession.minutes(endAtMs, ZoneId.systemDefault())) { minutes ->
                            endAtMs = OvertimeDialogs.nextOccurrence(minutes, minimum, ZoneId.systemDefault())
                        }
                    }, shape = MaterialTheme.shapes.medium) {
                        Text(text.eventTime(endAtMs, minimum), style = MaterialTheme.typography.titleMedium.copy(fontFeatureSettings = "tnum"))
                    }
                }
                Row(verticalAlignment = Alignment.Top) {
                    Icon(Icons.Outlined.Info, null, Modifier.size(18.dp).padding(top = 2.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(stringResource(R.string.overtimeNoMultiplier), Modifier.padding(start = DoneAtSpacing.s), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        },
        confirmButton = { TextButton(onClick = { onConfirm(endAtMs) }) { Text(stringResource(R.string.confirmOvertime)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.close)) } },
    )
}

internal object OvertimeDialogs {
    /**
     * The first moment at the picked clock reading that is not before
     * [minimumMs]: later today, or tomorrow once today's has passed, so an
     * evening shift's overtime can run past midnight. The picked minute of the
     * minimum itself means the minimum.
     */
    fun nextOccurrence(minutes: Int, minimumMs: Double, zone: ZoneId): Double {
        val floor = Instant.ofEpochMilli(minimumMs.toLong()).atZone(zone)
        var candidate = floor.toLocalDate().atTime(minutes / 60, minutes % 60).atZone(zone)
        val minuteOfMinimum = floor.withSecond(0).withNano(0)
        if (candidate.isBefore(minuteOfMinimum)) candidate = candidate.toLocalDate().plusDays(1).atTime(minutes / 60, minutes % 60).atZone(zone)
        return maxOf(candidate.toInstant().toEpochMilli().toDouble(), minimumMs)
    }
}
