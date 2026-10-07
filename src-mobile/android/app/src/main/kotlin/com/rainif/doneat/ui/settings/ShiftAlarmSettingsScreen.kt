package com.rainif.doneat.ui.settings

import android.app.AlarmManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.text.format.DateFormat
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Alarm
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.alarms.ShiftAlarmCoordinator
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.alarms.ShiftAlarmSettings
import com.rainif.doneat.core.domain.schedule.ShiftType
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.components.*
import com.rainif.doneat.ui.timer.TimerText
import java.text.DateFormat as JavaDateFormat
import java.time.LocalDate
import java.time.ZoneId
import java.util.Date
import java.util.UUID

@Composable
fun ShiftAlarmSettingsScreen(graph: AppGraph, onBack: () -> Unit, onRequestPlus: () -> Unit = {}) {
    val environment by graph.sessions.environment.collectAsStateWithLifecycle()
    val isPlus by graph.plus.authorized.collectAsStateWithLifecycle()
    ShiftAlarmSettingsScreen(graph.shiftAlarms,
        if (environment.isExtendedScheduleEnabled) environment.extendedSchedule?.content?.shiftTypes.orEmpty() else emptyList(),
        isPlus, onRequestPlus, onBack)
}

/** Honest device state and successful registrations only. There is no test-alarm action. */
@Composable
fun ShiftAlarmSettingsScreen(
    coordinator: ShiftAlarmCoordinator,
    workTypes: List<ShiftType>,
    isPlus: Boolean,
    onRequestPlus: () -> Unit,
    onBack: () -> Unit,
) {
    val settings by coordinator.settings.collectAsStateWithLifecycle()
    val status by coordinator.status.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val resources = LocalResources.current
    val locale = resources.configuration.locales[0]
    val text = TimerText(resources, locale, DateFormat.is24HourFormat(context), true)
    val on = settings.enabled && isPlus
    var picker by remember { mutableStateOf<LeadPicker?>(null) }
    LifecycleResumeEffect(coordinator) { coordinator.refresh(); onPauseOrDispose { } }
    fun permissionSettings() {
        val manager = context.getSystemService(AlarmManager::class.java)
        val exact = Build.VERSION.SDK_INT < 31 || manager.canScheduleExactAlarms()
        val intent = if (!exact) Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}"))
            else Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        runCatching { context.startActivity(intent) }
    }
    fun dateTime(ms: Long) = JavaDateFormat.getDateTimeInstance(JavaDateFormat.MEDIUM, JavaDateFormat.SHORT, locale).format(Date(ms))
    DoneAtPage(stringResource(R.string.shiftAlarmsTitle), onBack, stringResource(R.string.settings)) {
        SettingsGroup {
            SwitchRow(stringResource(R.string.shiftAlarmsTitle), on, { enabled ->
                if (enabled && !isPlus) onRequestPlus() else coordinator.setEnabled(enabled)
            }, badge = if (!isPlus) stringResource(R.string.plusSection) else null)
        }
        PageFooter(stringResource(R.string.shiftAlarmsIntro))
        if (isPlus && !status.entitlementAllowed) PageFooter(stringResource(R.string.shiftAlarmsNeedsVerifiedExpiry))
        if (on) {
            SettingsGroup {
                if (!status.exactAllowed || !status.notificationsAllowed) {
                    Text(stringResource(R.string.shiftAlarmsDenied), Modifier.padding(DoneAtSpacing.l),
                        style = MaterialTheme.typography.titleSmall)
                    Text(stringResource(if (!status.exactAllowed) R.string.shiftAlarmsDeniedNote else R.string.shiftAlarmsNotificationsOff), Modifier.padding(horizontal = DoneAtSpacing.l),
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    ActionRow(stringResource(R.string.shiftAlarmsAllow), ::permissionSettings, Icons.Outlined.Alarm)
                } else {
                    Text(status.coveredThroughMs?.let { Strings.shiftAlarmsCoveredThrough(resources, dateTime(it)) }
                        ?: stringResource(R.string.shiftAlarmsNoneUpcoming), Modifier.padding(DoneAtSpacing.l), style = MaterialTheme.typography.bodyMedium)
                    val note = when {
                        status.reachedSystemLimit || status.failedCount > 0 -> stringResource(R.string.shiftAlarmsLimitReached)
                        status.lifetime -> stringResource(R.string.shiftAlarmsLifetimeWindow)
                        status.windowEndMs != null -> Strings.shiftAlarmsUntilExpiry(resources, dateTime(status.windowEndMs!!))
                        else -> stringResource(R.string.shiftAlarmsNeedsVerifiedExpiry)
                    }
                    Text(note, Modifier.padding(horizontal = DoneAtSpacing.l), style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (status.refreshReminderUnavailable) Text(stringResource(R.string.shiftAlarmsReminderOff),
                        Modifier.padding(DoneAtSpacing.l), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    ActionRow(stringResource(R.string.shiftAlarmsRefresh), coordinator::refresh, Icons.Outlined.Refresh)
                }
            }
            Text(stringResource(R.string.shiftAlarmsLeadSection), Modifier.padding(horizontal = DoneAtSpacing.page, vertical = DoneAtSpacing.s),
                style = MaterialTheme.typography.titleSmall)
            SettingsGroup {
                val types = workTypes.filter { it.kind == ShiftType.Kind.WORK && !it.isArchived }
                @Composable fun leadRow(title: String, type: ShiftType?) {
                    val minutes = settings.leadMinutes(type?.id)
                    ListItem(headlineContent = { Text(title) }, supportingContent = { type?.let { shift ->
                        val start = LocalDate.of(2026, 1, 1).atStartOfDay(ZoneId.systemDefault()).plusMinutes(shift.startMinutes.toLong())
                        Text(Strings.shiftAlarmsStartsAt(resources, text.time(start.toInstant().toEpochMilli().toDouble())))
                    } }, trailingContent = {
                        TextButton(onClick = { picker = LeadPicker(title, type?.id) }) {
                            Text(minutes?.let { text.relativeDuration(it * 60_000.0) } ?: stringResource(R.string.shiftAlarmsLeadOff))
                        }
                    })
                }
                if (types.isEmpty()) leadRow(stringResource(R.string.shiftAlarmsBeforeWork), null)
                else types.forEachIndexed { index, type ->
                    leadRow(type.name, type)
                    if (index < types.lastIndex) RowDivider()
                }
            }
            if (status.exactAllowed && status.notificationsAllowed && status.accepted.isNotEmpty()) {
                Text(stringResource(R.string.shiftAlarmsUpcoming), Modifier.padding(horizontal = DoneAtSpacing.page, vertical = DoneAtSpacing.s),
                    style = MaterialTheme.typography.titleSmall)
                SettingsGroup {
                    status.accepted.take(5).forEachIndexed { index, alarm ->
                        val title = alarm.shiftName?.let { Strings.shiftAlarmTitle(resources, it, text.time(alarm.shiftStartAtMs.toDouble())) }
                            ?: Strings.shiftAlarmTitleFixed(resources, text.time(alarm.shiftStartAtMs.toDouble()))
                        ListItem(headlineContent = { Text(dateTime(alarm.fireAtMs)) }, supportingContent = { Text(title) },
                            leadingContent = { Icon(Icons.Outlined.Alarm, null) })
                        if (index < minOf(status.accepted.size, 5) - 1) RowDivider()
                    }
                }
            }
        }
    }
    picker?.let { choice ->
        AlertDialog(onDismissRequest = { picker = null }, title = { Text(choice.title) }, text = {
            Column(Modifier.heightIn(max = DoneAtSpacing.minTouch * 8).verticalScroll(rememberScrollState())) {
                val values: List<Int?> = (if (choice.id != null) listOf(null) else emptyList()) + ShiftAlarmSettings.LEAD_CHOICES.sorted()
                values.forEach { minutes ->
                    ChoiceRow(minutes?.let { text.relativeDuration(it * 60_000.0) } ?: stringResource(R.string.shiftAlarmsLeadOff),
                        selected = settings.leadMinutes(choice.id) == minutes, onSelect = {
                            coordinator.setLead(choice.id, minutes); picker = null
                        })
                }
            }
        }, confirmButton = {})
    }
}
private data class LeadPicker(val title: String, val id: UUID?)
