package com.rainif.doneat.ui.settings

import android.Manifest
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.core.net.toUri
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.alarms.ShiftAlarms
import com.rainif.doneat.core.domain.alarms.ShiftAlarmSettings
import com.rainif.doneat.core.domain.schedule.ShiftType
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.PlusPendingAction
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.components.*
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.UUID

@Composable
fun ShiftAlarmSettingsScreen(graph: AppGraph, open: (Route) -> Unit, back: () -> Unit) {
    val context = LocalContext.current
    val resources = LocalResources.current
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val records by graph.records.state.collectAsStateWithLifecycle()
    val registry by ShiftAlarms.sync(context).state.collectAsStateWithLifecycle()
    val plus by graph.plus.authorized.collectAsStateWithLifecycle()
    val store by graph.plus.state.collectAsStateWithLifecycle()
    val session by graph.sessions.session.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val settings = device.shiftAlarms
    var permissionVersion by remember { mutableIntStateOf(0) }
    var picking by remember { mutableStateOf(false) }
    var pickingType by remember { mutableStateOf<UUID?>(null) }
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) {
            permissionVersion++
            scope.launch { graph.shiftAlarms.reconcile() }
        } }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
    val exact = remember(permissionVersion) { ShiftAlarms.exactAllowed(context) }
    val notifications = remember(permissionVersion) { ShiftAlarms.notificationsAllowed(context) }
    val fullScreen = remember(permissionVersion) { ShiftAlarms.fullScreenAllowed(context) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { permissionVersion++; scope.launch { graph.shiftAlarms.reconcile(true) } }
    val now = System.currentTimeMillis()
    val waiting = registry.waiting(now)
    val zone = session.countdownZone
    val formatter = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
        .withLocale(resources.configuration.locales[0]).withZone(zone)
    fun format(at: Long) = formatter.format(Instant.ofEpochMilli(at))
    fun edit(change: (ShiftAlarmSettings) -> ShiftAlarmSettings) {
        scope.launch { graph.settings.updateDevice { it.copy(shiftAlarms = change(it.shiftAlarms)) } }
    }
    fun systemPage(action: String) {
        runCatching { context.startActivity(Intent(action, "package:${context.packageName}".toUri())) }
    }
    val types = records.extendedSchedule?.takeIf { it.isEnabled }?.content?.shiftTypes.orEmpty()
        .filter { it.kind == ShiftType.Kind.WORK && !it.isArchived }
    DoneAtPage(stringResource(R.string.shiftAlarmsTitle), back, stringResource(R.string.settings)) {
        SettingsGroup(footer = stringResource(R.string.shiftAlarmsIntro)) {
            SwitchRow(stringResource(R.string.shiftAlarmsTitle), settings.enabled, { on ->
                if (on && !plus) open(Route.PlusFor(PlusPendingAction.ShiftAlarms)) else edit { it.copy(enabled = on) }
            }, badge = if (!plus) "Plus" else null)
        }
        if (settings.enabled) {
            if (!exact || !notifications) SettingsGroup(footer = stringResource(R.string.shiftAlarmsAndroidAccess)) {
                if (!notifications) ActionRow(stringResource(R.string.shiftAlarmsAllow), {
                    if (Build.VERSION.SDK_INT >= 33 && !device.notificationPermissionRequested) {
                        scope.launch { graph.settings.updateDevice { it.copy(notificationPermissionRequested = true) } }
                        permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                    } else systemPage(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                })
                if (!exact) ActionRow(stringResource(R.string.allowExactReminders), { if (Build.VERSION.SDK_INT >= 31) systemPage(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM) })
            }
            SettingsGroup(footer = stringResource(R.string.shiftAlarmsFullScreenNote)) {
                NavigationRow(stringResource(R.string.shiftAlarmsFullScreen), {
                    if (Build.VERSION.SDK_INT >= 34) systemPage(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                    else systemPage(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                }, value = stringResource(if (fullScreen) R.string.shiftAlarmsOnShort else R.string.disabledShort))
            }
            SettingsGroup(footer = when {
                registry.failed > 0 -> stringResource(R.string.shiftAlarmsLimitReached)
                registry.lifetime -> stringResource(R.string.shiftAlarmsLifetimeWindow)
                registry.untilMs != null -> Strings.shiftAlarmsUntilExpiry(resources, format(registry.untilMs!!))
                plus && exact && notifications && store.status == com.rainif.doneat.plus.PlusStatus.SUBSCRIBED && store.verifiedSubscriptionExpiresAtMs == null -> stringResource(R.string.plusAndroidStoreOffline)
                else -> null
            }) {
                ValueRow(stringResource(R.string.shiftAlarmsUpcoming), registry.coveredThroughMs?.takeIf { it > now }?.let {
                    Strings.shiftAlarmsCoveredThrough(resources, format(it))
                } ?: stringResource(R.string.shiftAlarmsNoneUpcoming))
                ActionRow(stringResource(R.string.shiftAlarmsRefresh), { graph.plus.refresh(); scope.launch { graph.shiftAlarms.reconcile(true) } })
            }
        }
        SettingsGroup(stringResource(R.string.shiftAlarmsLeadSection), footer = stringResource(R.string.shiftAlarmsAndroidNote)) {
            NavigationRow(stringResource(R.string.shiftAlarmsBeforeWork), { pickingType = null; picking = true },
                value = Strings.minutesShort(resources, settings.defaultLeadMinutes.toString()))
            types.forEach { type ->
                RowDivider()
                NavigationRow(type.name, { pickingType = type.id; picking = true }, value = settings.leadMinutes(type.id)?.let {
                    Strings.minutesShort(resources, it.toString())
                } ?: stringResource(R.string.shiftAlarmsLeadOff))
            }
        }
        if (settings.enabled && waiting.isNotEmpty()) SettingsGroup(stringResource(R.string.shiftAlarmsUpcoming)) {
            waiting.take(5).forEachIndexed { index, entry ->
                if (index > 0) RowDivider()
                ValueRow(entry.title, format(entry.alarm.fireAtMs))
            }
        }
    }
    if (picking) AlertDialog(onDismissRequest = { picking = false }, title = { Text(stringResource(R.string.shiftAlarmsLeadSection)) },
        text = { Column(Modifier.verticalScroll(rememberScrollState())) {
            if (pickingType != null) ChoiceRow(stringResource(R.string.shiftAlarmsLeadOff), settings.leadMinutes(pickingType) == null, {
                edit { it.copy(silencedShiftTypeIDs = it.silencedShiftTypeIDs + pickingType!!) }; picking = false
            })
            ShiftAlarmSettings.LEAD_CHOICES.sorted().forEach { lead ->
                ChoiceRow(Strings.minutesShort(resources, lead.toString()), settings.leadMinutes(pickingType) == lead, {
                    edit { s -> if (pickingType == null) s.copy(defaultLeadMinutes = lead)
                        else s.copy(leadMinutesByShiftType = s.leadMinutesByShiftType + (pickingType!! to lead), silencedShiftTypeIDs = s.silencedShiftTypeIDs - pickingType!!) }
                    picking = false
                })
            }
        } }, confirmButton = { TextButton(onClick = { picking = false }) { Text(stringResource(R.string.done)) } })
}
