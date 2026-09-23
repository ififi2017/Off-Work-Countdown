package com.rainif.doneat.ui.settings

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.DirectionsWalk
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Contrast
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.EditCalendar
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.LightMode
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.RateReview
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import com.rainif.doneat.R
import com.rainif.doneat.core.data.DeviceSettings
import com.rainif.doneat.core.designsystem.CelebratingBrandMark
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.supportsDynamicColor
import com.rainif.doneat.core.domain.records.RecordState
import com.rainif.doneat.core.domain.records.SyncedPreferences
import com.rainif.doneat.core.domain.schedule.ShiftCycleRule
import com.rainif.doneat.core.domain.settings.AppLanguages
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.components.ActionRow
import com.rainif.doneat.ui.components.ChoiceRow
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.NavigationRow
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.components.SettingsFooter
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.components.SwitchRow
import org.json.JSONArray

/** Applies an edit to the settings; the repository drops edits that change nothing. */
typealias EditPreferences = ((SyncedPreferences) -> SyncedPreferences) -> Unit

/** What each settings row shows as its current value (iOS `ShiftSessionStore+Labels`, `AppText`). */
object SettingsLabels {
    @Composable
    fun schedule(p: SyncedPreferences, records: RecordState): String {
        val extended = records.extendedSchedule?.takeIf { it.isEnabled }
        if (extended != null) {
            return stringResource(
                when (extended.content.rule?.preset) {
                    ShiftCycleRule.Preset.WEEKLY -> R.string.scheduleClassic
                    ShiftCycleRule.Preset.ALTERNATING_WEEKS -> R.string.scheduleAlternating
                    ShiftCycleRule.Preset.ROTATION, ShiftCycleRule.Preset.CUSTOM -> R.string.scheduleRotation
                    null -> R.string.scheduleFreeCalendar
                },
            )
        }
        return stringResource(
            when (p.scheduleMode) {
                "alternating" -> R.string.scheduleAlternating
                "rotation" -> R.string.scheduleRotation
                "off" -> R.string.scheduleOff
                else -> R.string.scheduleClassic
            },
        )
    }

    @Composable
    fun salary(p: SyncedPreferences) = stringResource(
        when {
            !p.salaryEnabled -> R.string.disabledShort
            p.salaryType == "daily" -> R.string.daily
            else -> R.string.monthly
        },
    )

    @Composable
    fun notificationMode(mode: String) = stringResource(
        when (mode) {
            "simple" -> R.string.notificationModeSimple
            "milestones" -> R.string.notificationModeMilestones
            else -> R.string.notificationModeOff
        },
    )

    @Composable
    fun health(p: SyncedPreferences): String {
        if (!p.microBreakEnabled) return stringResource(R.string.disabledShort)
        return Strings.minutesShort(LocalResources.current, p.microBreakIntervalMinutes.toString())
    }

    @Composable
    fun theme(theme: String) = stringResource(
        when (theme) {
            "light" -> R.string.light
            "dark" -> R.string.dark
            else -> R.string.auto
        },
    )

    @Composable
    fun language(override: String?) =
        override?.let { code -> AppLanguages.supported.firstOrNull { it.first == code }?.second } ?: stringResource(R.string.auto)
}

/** The settings list (iOS `SettingsSection`): shift, reminders, appearance, records & data, about. Plus is a title action. */
@Composable
fun SettingsHomeScreen(p: SyncedPreferences, records: RecordState, open: (Route) -> Unit) {
    val context = LocalContext.current
    DoneAtPage(
        title = stringResource(R.string.settings),
        actions = {
            TextButton(onClick = { open(Route.Plus) }) {
                Icon(Icons.Outlined.StarOutline, contentDescription = null, modifier = Modifier.padding(end = DoneAtSpacing.xs))
                // The brand name, not a translated word, as iOS writes it.
                Text("Plus")
            }
        },
    ) {
        SettingsGroup(stringResource(R.string.shiftSection)) {
            NavigationRow(stringResource(R.string.workSchedule), { open(Route.Schedule) }, Icons.Outlined.EditCalendar, SettingsLabels.schedule(p, records))
            RowDivider()
            NavigationRow(stringResource(R.string.salarySettings), { open(Route.Salary) }, Icons.Outlined.Payments, SettingsLabels.salary(p))
        }
        SettingsGroup(stringResource(R.string.remindersSection)) {
            NavigationRow(stringResource(R.string.shiftReminders), { open(Route.Notifications) }, Icons.Outlined.NotificationsActive, SettingsLabels.notificationMode(p.notificationMode))
            RowDivider()
            NavigationRow(stringResource(R.string.microBreakReminder), { open(Route.Health) }, Icons.AutoMirrored.Outlined.DirectionsWalk, SettingsLabels.health(p))
        }
        SettingsGroup(stringResource(R.string.appearanceSection)) {
            NavigationRow(stringResource(R.string.theme), { open(Route.Theme) }, Icons.Outlined.Contrast, SettingsLabels.theme(p.theme))
            RowDivider()
            NavigationRow(stringResource(R.string.chooselanguage), { open(Route.Language) }, Icons.Outlined.Language, SettingsLabels.language(p.languageOverride))
        }
        SettingsGroup(stringResource(R.string.recordsDataSection)) {
            NavigationRow(stringResource(R.string.recordsDataTitle), { open(Route.RecordsData) }, Icons.Outlined.Storage)
        }
        SettingsGroup(stringResource(R.string.aboutSection)) {
            NavigationRow(stringResource(R.string.aboutProject), { open(Route.About) }, Icons.Outlined.Info)
            RowDivider()
            ActionRow(stringResource(R.string.rateAppGooglePlay), { openPlayListing(context) }, Icons.Outlined.RateReview, Icons.AutoMirrored.Outlined.OpenInNew)
        }
    }
}

/** The Play listing: the store app when present, the web page otherwise. Never the in-app review card, which may not appear. */
fun openPlayListing(context: Context) {
    val id = context.packageName
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, "market://details?id=$id".toUri()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
        openUrl(context, "https://play.google.com/store/apps/details?id=$id")
    }
}

fun openUrl(context: Context, url: String) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
        // No browser: nothing sensible to do, and nothing to lose.
    }
}

/** Automatic, light or dark (iOS `ThemeSettingsView`), plus wallpaper colours where Android offers them. */
@Composable
fun ThemeScreen(p: SyncedPreferences, device: DeviceSettings, edit: EditPreferences, setDynamic: (Boolean) -> Unit, onBack: () -> Unit) {
    DoneAtPage(stringResource(R.string.theme), onBack, stringResource(R.string.settings)) {
        SettingsGroup {
            ChoiceRow(stringResource(R.string.auto), p.theme == "auto", { edit { it.copy(theme = "auto") } }, Icons.Outlined.Contrast)
            RowDivider()
            ChoiceRow(stringResource(R.string.light), p.theme == "light", { edit { it.copy(theme = "light") } }, Icons.Outlined.LightMode)
            RowDivider()
            ChoiceRow(stringResource(R.string.dark), p.theme == "dark", { edit { it.copy(theme = "dark") } }, Icons.Outlined.DarkMode)
        }
        if (supportsDynamicColor) {
            SettingsGroup {
                SwitchRow(stringResource(R.string.wallpaperColors), device.dynamicColor, setDynamic)
            }
        }
    }
}

/** "System" first, then each language named in itself, so anyone stranded in one they cannot read can find their way out. */
@Composable
fun LanguageScreen(p: SyncedPreferences, select: (String?) -> Unit, onBack: () -> Unit) {
    DoneAtPage(stringResource(R.string.chooselanguage), onBack, stringResource(R.string.settings)) {
        SettingsGroup(footer = stringResource(R.string.languageFooter)) {
            ChoiceRow(stringResource(R.string.auto), p.languageOverride == null, { select(null) })
            AppLanguages.supported.forEach { (code, name) ->
                RowDivider(inset = false)
                ChoiceRow(name, p.languageOverride == code, { select(code) })
            }
        }
    }
}

/**
 * The health reminder (iOS `HealthReminderSettingsView`): on/off and an
 * interval clamped to 20–120 minutes when the field is committed or left.
 */
@Composable
fun HealthScreen(p: SyncedPreferences, edit: EditPreferences, onBack: () -> Unit) {
    var draft by rememberSaveable(p.microBreakIntervalMinutes) { mutableStateOf(p.microBreakIntervalMinutes.toString()) }
    val latest by rememberUpdatedState(p.microBreakIntervalMinutes)
    val commit = remember(edit) {
        { typed: String ->
            val clamped = (typed.trim().toIntOrNull() ?: latest).coerceIn(20, 120)
            draft = clamped.toString()
            edit { it.copy(microBreakIntervalMinutes = clamped) }
        }
    }
    val currentDraft by rememberUpdatedState(draft)
    DisposableEffect(Unit) { onDispose { if (currentDraft != latest.toString()) commit(currentDraft) } }

    DoneAtPage(stringResource(R.string.microBreakReminder), onBack, stringResource(R.string.settings)) {
        SettingsGroup(footer = stringResource(R.string.microBreakEffectiveTimeNote)) {
            SwitchRow(stringResource(R.string.microBreakReminder), p.microBreakEnabled, { on -> edit { it.copy(microBreakEnabled = on) } })
            if (p.microBreakEnabled) {
                RowDivider(inset = false)
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.s),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m),
                ) {
                    Text(stringResource(R.string.microBreakInterval), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                    OutlinedTextField(
                        value = draft,
                        onValueChange = { draft = it.filter(Char::isDigit).take(3) },
                        modifier = Modifier.width(88.dp),
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { commit(draft) }),
                    )
                    Text(stringResource(R.string.minutesUnit), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** Version, links and acknowledgements (iOS `AboutView`). */
@Composable
fun AboutScreen(open: (Route) -> Unit, onBack: () -> Unit) {
    val context = LocalContext.current
    val version = remember { runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() ?: "" }
    DoneAtPage(stringResource(R.string.aboutProject), onBack, stringResource(R.string.settings)) {
        SettingsGroup {
            Column(
                Modifier.fillMaxWidth().padding(vertical = DoneAtSpacing.xl),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs),
            ) {
                CelebratingBrandMark(stringResource(R.string.app_name), Modifier.size(120.dp).padding(bottom = DoneAtSpacing.s), showsDepth = true)
                Text("DoneAt", style = MaterialTheme.typography.headlineSmall)
                Text("fi_niaR Studio", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("${stringResource(R.string.version)} $version", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        SettingsGroup {
            NavigationRow(stringResource(R.string.acknowledgements), { open(Route.Acknowledgements) }, Icons.AutoMirrored.Outlined.MenuBook)
        }
        SettingsGroup {
            ActionRow(stringResource(R.string.privacyPolicy), { openUrl(context, "https://doneat.app/privacy") }, trailing = Icons.AutoMirrored.Outlined.OpenInNew)
            RowDivider(inset = false)
            ActionRow(stringResource(R.string.githubRepository), { openUrl(context, "https://github.com/ififi2017/Off-Work-Countdown") }, trailing = Icons.AutoMirrored.Outlined.OpenInNew)
            RowDivider(inset = false)
            ActionRow(stringResource(R.string.visitOfficialWebsite), { openUrl(context, "https://doneat.app/") }, trailing = Icons.AutoMirrored.Outlined.OpenInNew)
            RowDivider(inset = false)
            ActionRow(stringResource(R.string.downloadDesktopApp), { openUrl(context, "https://doneat.app/download") }, trailing = Icons.AutoMirrored.Outlined.OpenInNew)
        }
    }
}

/** The holiday data's sources and licences, from the same bundled file iOS shows. */
@Composable
fun AcknowledgementsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val attributions = remember {
        runCatching {
            val array = JSONArray(context.assets.open("HolidayTemplateAttributions.json").bufferedReader().use { it.readText() })
            (0 until array.length()).map { i -> array.getJSONObject(i).let { Triple(it.getString("name"), it.getString("sourceURL"), it.getString("license")) } }
        }.getOrDefault(emptyList())
    }
    DoneAtPage(stringResource(R.string.acknowledgements), onBack, stringResource(R.string.aboutProject)) {
        attributions.forEach { (name, url, license) ->
            SettingsGroup {
                ActionRow(name, { openUrl(context, url) }, trailing = Icons.AutoMirrored.Outlined.OpenInNew)
                RowDivider(inset = false)
                Text(
                    license,
                    modifier = Modifier.padding(DoneAtSpacing.l),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** A page another task builds (the timer in T16, records in T17, focus in T18, Plus in T20, data in T11): its title only. */
@Composable
fun PendingScreen(title: String, onBack: (() -> Unit)?, backLabel: String?) {
    DoneAtPage(title, onBack, backLabel) {}
}
