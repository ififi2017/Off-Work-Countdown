package com.rainif.doneat.ui.settings

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtPrimaryButton
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.records.SyncedPreferences
import com.rainif.doneat.reminders.ReminderCapability
import com.rainif.doneat.reminders.Reminders
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.components.ActionRow
import com.rainif.doneat.ui.components.ChoiceRow
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.components.PageFooter
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.components.SwitchRow
import com.rainif.doneat.ui.components.ValueRow

/** Whether the app may post notifications, and whether it may still ask. */
enum class NotificationAccess { ALLOWED, NOT_ASKED, DENIED }

fun notificationAccess(context: Context, requestedBefore: Boolean): NotificationAccess {
    if (Reminders.capability(context).notificationsAllowed) return NotificationAccess.ALLOWED
    val canAsk = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !requestedBefore &&
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
    return if (canAsk) NotificationAccess.NOT_ASKED else NotificationAccess.DENIED
}

/**
 * Shift reminders (iOS `NotificationDesignView`). Choosing a reminder asks
 * for notifications once; a refusal turns the reminder back off, as on iOS,
 * and from then on the page points to system settings instead of asking
 * again. Without the exact-alarm grant the page says reminders may be late.
 */
@Composable
fun NotificationsScreen(
    p: SyncedPreferences,
    permissionRequested: Boolean,
    edit: EditPreferences,
    markPermissionRequested: () -> Unit,
    isPlus: Boolean,
    open: (Route) -> Unit,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    // Re-read on every return to the app: both grants change in system settings.
    var refresh by remember { mutableIntStateOf(0) }
    LifecycleResumeEffect(Unit) {
        refresh++
        onPauseOrDispose {}
    }
    val access = remember(refresh, permissionRequested) { notificationAccess(context, permissionRequested) }
    val exactAllowed = remember(refresh) { Reminders.capability(context).exactAlarmsAllowed }

    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        markPermissionRequested()
        refresh++
        if (!granted) edit { it.copy(notificationMode = "off") }
    }
    fun choose(mode: String) {
        edit { it.copy(notificationMode = mode) }
        if (mode != "off" && access == NotificationAccess.NOT_ASKED && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            request.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    DoneAtPage(stringResource(R.string.shiftReminders), onBack, stringResource(R.string.settings)) {
        if (access == NotificationAccess.DENIED) {
            DeniedContent(context)
            return@DoneAtPage
        }
        SettingsGroup {
            ChoiceRow(stringResource(R.string.notificationModeOff), p.notificationMode == "off", { choose("off") })
            RowDivider(inset = false)
            ChoiceRow(stringResource(R.string.notificationModeSimple), p.notificationMode == "simple", { choose("simple") })
            RowDivider(inset = false)
            ChoiceRow(stringResource(R.string.notificationModeMilestones), p.notificationMode == "milestones", { choose("milestones") })
        }
        if (access == NotificationAccess.ALLOWED && !exactAllowed) {
            SettingsGroup(footer = stringResource(R.string.remindersMayBeLate)) {
                ActionRow(
                    stringResource(R.string.allowExactReminders),
                    { ReminderCapability.exactAlarmSettings(context)?.let(context::startActivity) },
                    trailing = Icons.AutoMirrored.Outlined.OpenInNew,
                )
            }
        }
        // Moved here from the lunch page on iOS: these decide whether something is announced.
        if (p.lunchEnabled) {
            SettingsGroup(stringResource(R.string.lunchBreak)) {
                SwitchRow(stringResource(R.string.lunchStartReminder), p.lunchStartReminderEnabled, { on -> edit { it.copy(lunchStartReminderEnabled = on) } })
                RowDivider(inset = false)
                SwitchRow(stringResource(R.string.lunchEndReminder), p.lunchEndReminderEnabled, { on -> edit { it.copy(lunchEndReminderEnabled = on) } })
            }
        }
        SettingsGroup(stringResource(R.string.cycleEndSummaryNotificationTitle), footer = stringResource(R.string.cycleEndSummaryNotificationNote)) {
            SwitchRow(
                stringResource(R.string.cycleEndSummaryNotificationTitle),
                checked = isPlus && p.cycleEndSummaryNotificationEnabled,
                onCheckedChange = { on -> if (isPlus) edit { it.copy(cycleEndSummaryNotificationEnabled = on) } else open(Route.Plus) },
                badge = if (isPlus) null else stringResource(R.string.plusStatusSubscribed),
            )
        }
        PageFooter(stringResource(R.string.notificationPrivacyNote))
    }
}

@Composable
private fun DeniedContent(context: Context) {
    SettingsGroup {
        Column(Modifier.fillMaxWidth().padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
            Icon(Icons.Outlined.NotificationsOff, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Text(stringResource(R.string.notificationDeniedTitle), style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.notificationDeniedBody), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            DoneAtPrimaryButton(stringResource(R.string.notificationOpenSettings), { context.startActivity(ReminderCapability.notificationSettings(context)) }, Modifier.fillMaxWidth())
        }
    }
    SettingsGroup(stringResource(R.string.notificationCapability)) {
        ValueRow(stringResource(R.string.notificationLocal), stringResource(R.string.notificationDeniedStatus), MaterialTheme.colorScheme.error)
    }
    PageFooter(stringResource(R.string.notificationPrivacyNote))
}
