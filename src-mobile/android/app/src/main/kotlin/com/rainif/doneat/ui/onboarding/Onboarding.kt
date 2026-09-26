package com.rainif.doneat.ui.onboarding

import android.Manifest
import android.content.Context
import android.net.Uri
import android.os.Build
import android.text.format.DateFormat
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.LockOpen
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material.icons.outlined.Widgets
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.data.FirstRunRestore
import com.rainif.doneat.core.data.RestorePreview
import com.rainif.doneat.core.designsystem.DoneAtMotion
import com.rainif.doneat.core.designsystem.DoneAtPrimaryButton
import com.rainif.doneat.core.designsystem.CelebratingBrandMark
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.designsystem.LocalDoneAtMotion
import com.rainif.doneat.core.domain.records.SyncedPreferences
import com.rainif.doneat.core.domain.salary.NumberInput
import com.rainif.doneat.core.domain.settings.PreferencesRules
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.timer.EarningsGate
import com.rainif.doneat.ui.components.ChoiceRow
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.components.SettingsFooter
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.components.SwitchRow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.DateFormatSymbols
import java.text.NumberFormat
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** The first-run pages, in order (iOS `OnboardingPages`, without the iOS-only showcases; Plus arrives with T20). */
enum class SetupPage { WELCOME, SCHEDULE, REMINDERS, PRIVACY, FINALE }

/**
 * First launch (plan 01 §6.1): set up a schedule, or restore a backup file.
 *
 * Every choice goes into the setup draft on this device, which survives the
 * process being killed; nothing reaches the records archive until the last
 * page commits it once. A restored backup that carries settings skips the
 * rest; one that does not keeps its records and continues setup.
 */
@Composable
fun SetupFlow(graph: AppGraph) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val prefs by graph.settings.preferences.collectAsStateWithLifecycle()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    // Kept on disk with the draft, so an interruption of any kind resumes on the same page.
    var page by remember { mutableStateOf(SetupPage.entries.firstOrNull { it.name == graph.settings.device.value.setupPage } ?: SetupPage.WELCOME) }
    var forward by rememberSaveable { mutableStateOf(true) }
    /** iOS applies the reminder page's defaults once per launch, so turning them off and coming back does not undo that. */
    var reminderDefaultsApplied by rememberSaveable { mutableStateOf(false) }
    var restoredWithoutSettings by rememberSaveable { mutableStateOf(false) }
    val edit: ((SyncedPreferences) -> SyncedPreferences) -> Unit = { change -> scope.launch { graph.settings.edit(change) } }

    fun go(to: SetupPage) {
        forward = to.ordinal > page.ordinal
        page = to
        scope.launch { graph.settings.updateDevice { it.copy(setupPage = to.name) } }
    }
    BackHandler(enabled = page != SetupPage.WELCOME) { go(SetupPage.entries[page.ordinal - 1]) }

    val notificationRequest = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        scope.launch { graph.settings.updateDevice { d -> d.copy(notificationPermissionRequested = true, ongoingEnabled = d.ongoingEnabled && granted) } }
        go(SetupPage.PRIVACY)
    }

    val motion = LocalDoneAtMotion.current
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface).safeDrawingPadding()) {
        AnimatedContent(
            targetState = page,
            transitionSpec = {
                if (motion.reduced) {
                    fadeIn(tween(DoneAtMotion.REDUCED_MS)) togetherWith fadeOut(tween(DoneAtMotion.REDUCED_MS))
                } else {
                    val sign = if (forward) 1 else -1
                    (fadeIn(tween(DoneAtMotion.STATE_ENTER_MS, easing = motion.emphasizedDecelerate)) + slideInHorizontally(motion.phase()) { sign * it / 12 }) togetherWith
                        (fadeOut(tween(DoneAtMotion.STATE_EXIT_MS, easing = motion.emphasizedDecelerate)) + slideOutHorizontally(motion.phase()) { -sign * it / 12 })
                }
            },
            label = "setupPage",
        ) { current ->
            val back = if (current == SetupPage.WELCOME) null else { { go(SetupPage.entries[current.ordinal - 1]) } }
            when (current) {
                SetupPage.WELCOME -> WelcomePage(graph, onStart = { go(SetupPage.SCHEDULE) }, onRestoredWithoutSettings = {
                    restoredWithoutSettings = true
                    go(SetupPage.SCHEDULE)
                })
                SetupPage.SCHEDULE -> SchedulePage(prefs, edit, restoredWithoutSettings, back) { go(SetupPage.REMINDERS) }
                SetupPage.REMINDERS -> {
                    if (!reminderDefaultsApplied) {
                        reminderDefaultsApplied = true
                        edit(PreferencesRules::onboardingReminderDefaults)
                    }
                    RemindersPage(prefs, edit, device.ongoingEnabled, { enabled ->
                        scope.launch { graph.settings.updateDevice { it.copy(ongoingEnabled = enabled) } }
                    }, back) {
                        // As iOS: asked once, when leaving the page with a reminder on; a refusal is handled in Settings.
                        val wantsNotifications = prefs.notificationMode != "off" || prefs.microBreakEnabled ||
                            prefs.lunchStartReminderEnabled || prefs.lunchEndReminderEnabled || device.ongoingEnabled
                        if (wantsNotifications && !device.notificationPermissionRequested && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            notificationRequest.launch(Manifest.permission.POST_NOTIFICATIONS)
                        } else {
                            // A previous refusal survives revisiting this page. Never
                            // finish setup with the ongoing toggle claiming access.
                            if (device.ongoingEnabled && !com.rainif.doneat.reminders.Reminders.capability(context).notificationsAllowed) {
                                scope.launch { graph.settings.updateDevice { it.copy(ongoingEnabled = false) } }
                            }
                            go(SetupPage.PRIVACY)
                        }
                    }
                }
                SetupPage.PRIVACY -> PrivacyPage(back) { go(SetupPage.FINALE) }
                SetupPage.FINALE -> FinalePage(back) { scope.launch { graph.settings.completeSetup() } }
            }
        }
    }
}

/** A setup page: optional back arrow, centred title and body, content, then the continue button at the bottom. */
@Composable
private fun SetupScaffold(
    title: String,
    body: String?,
    onBack: (() -> Unit)?,
    continueLabel: String,
    onContinue: () -> Unit,
    hero: (@Composable () -> Unit)? = null,
    secondaryAction: (@Composable ColumnScope.() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.heightIn(min = 56.dp).padding(horizontal = DoneAtSpacing.xs)) {
            if (onBack != null) {
                IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = stringResource(R.string.onboardingBack)) }
            }
        }
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            Column(
                Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min = maxHeight),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Column(Modifier.widthIn(max = 560.dp).padding(horizontal = DoneAtSpacing.xl), horizontalAlignment = Alignment.CenterHorizontally) {
                    if (hero != null) {
                        hero()
                        Spacer(Modifier.size(DoneAtSpacing.xl))
                    }
                    Text(title, style = MaterialTheme.typography.headlineMedium, textAlign = TextAlign.Center, modifier = Modifier.semantics { heading() })
                    if (body != null) {
                        Text(
                            body,
                            modifier = Modifier.padding(top = DoneAtSpacing.m),
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
                Spacer(Modifier.size(DoneAtSpacing.xxl))
                Column(Modifier.widthIn(max = 560.dp), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l), content = content)
            }
        }
        DoneAtPrimaryButton(
            continueLabel,
            onContinue,
            Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = DoneAtSpacing.xl, vertical = DoneAtSpacing.l).align(Alignment.CenterHorizontally),
        )
        secondaryAction?.invoke(this)
    }
}

@Composable
private fun WelcomePage(graph: AppGraph, onStart: () -> Unit, onRestoredWithoutSettings: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var preview by remember { mutableStateOf<RestorePreview?>(null) }
    var failed by remember { mutableStateOf(false) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val result = withContext(Dispatchers.IO) { readBackup(context, uri)?.let { FirstRunRestore.preview(it, graph.nowMs()) } ?: RestorePreview.TooLarge }
            if (result is RestorePreview.Ready) preview = result else failed = true
        }
    }

    SetupScaffold(
        stringResource(R.string.app_name), stringResource(R.string.landingTagline), null, stringResource(R.string.continue_), onStart,
        hero = { CelebratingBrandMark(stringResource(R.string.app_name), Modifier.size(112.dp)) },
    ) {
        SettingsGroup {
            Feature(Icons.Outlined.Schedule, stringResource(R.string.landingFeature1Title), stringResource(R.string.onboardingShiftBody))
            RowDivider()
            Feature(Icons.Outlined.CloudOff, stringResource(R.string.onboardingOfflineTitle), stringResource(R.string.onboardingOfflineBody))
            RowDivider()
            Feature(Icons.Outlined.Widgets, stringResource(R.string.onboardingSystemTitle), stringResource(R.string.onboardingSystemBody))
        }
        TextButton(
            // A backup is a JSON file, but file providers label it inconsistently.
            onClick = { pick.launch(arrayOf("application/json", "application/octet-stream", "text/plain")) },
            modifier = Modifier.align(Alignment.CenterHorizontally).padding(horizontal = DoneAtSpacing.xl),
        ) { Text(stringResource(R.string.onboardingRestoreFromFile), textAlign = TextAlign.Center) }
    }

    (preview as? RestorePreview.Ready)?.let { ready ->
        val res = LocalResources.current
        AlertDialog(
            onDismissRequest = { preview = null },
            title = { Text(stringResource(R.string.recordsImportPreviewTitle)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs)) {
                    Text(Strings.recordsImportAdded(res, ready.itemCount.toString()))
                    if (ready.skipped > 0) Text(Strings.recordsImportSkipped(res, ready.skipped.toString()))
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    preview = null
                    scope.launch {
                        if (!FirstRunRestore.commit(graph.records, ready)) {
                            failed = true
                            return@launch
                        }
                        graph.settings.finishRestore(ready.hasSettings)
                        if (!ready.hasSettings) onRestoredWithoutSettings()
                    }
                }) { Text(stringResource(R.string.recordsImport)) }
            },
            dismissButton = { TextButton(onClick = { preview = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
    if (failed) {
        AlertDialog(
            onDismissRequest = { failed = false },
            text = { Text(stringResource(R.string.recordsOperationImportFailed)) },
            confirmButton = { TextButton(onClick = { failed = false }) { Text(stringResource(R.string.close)) } },
        )
    }
}

/** Reads at most one byte past the limit, so an oversized file is refused without loading it whole. */
private fun readBackup(context: Context, uri: Uri): ByteArray? =
    com.rainif.doneat.ui.files.BackupFiles.read(context, uri, FirstRunRestore.MAX_BYTES)

@Composable
private fun Feature(icon: ImageVector, title: String, body: String) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(body) },
        leadingContent = {
            Box(Modifier.size(40.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape), contentAlignment = Alignment.Center) {
                Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
            }
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}

@Composable
private fun SetupHeroIcon(icon: ImageVector) {
    Box(Modifier.size(52.dp).background(MaterialTheme.colorScheme.primaryContainer, MaterialTheme.shapes.medium), contentAlignment = Alignment.Center) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(26.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
    }
}

@Composable
private fun SchedulePage(p: SyncedPreferences, edit: ((SyncedPreferences) -> SyncedPreferences) -> Unit, restored: Boolean, onBack: (() -> Unit)?, onContinue: () -> Unit) {
    val pickTime = rememberTimePicker()
    SetupScaffold(stringResource(R.string.onboardingScheduleTitle), stringResource(R.string.onboardingScheduleBody), onBack, stringResource(R.string.continue_), onContinue,
        hero = { SetupHeroIcon(Icons.Outlined.Schedule) }) {
        if (restored) {
            SettingsGroup { Text(stringResource(R.string.firstRunCloudNeedsSetup), Modifier.padding(DoneAtSpacing.l), style = MaterialTheme.typography.bodyMedium) }
        }
        SettingsGroup {
            TimeRow(stringResource(R.string.startTime), p.startMinutes) { pickTime(p.startMinutes) { m -> edit { it.copy(startMinutes = m) } } }
            RowDivider(inset = false)
            TimeRow(stringResource(R.string.endTime), p.endMinutes) { pickTime(p.endMinutes) { m -> edit { it.copy(endMinutes = m) } } }
        }
        SettingsGroup(footer = stringResource(R.string.onboardingCustomScheduleNote)) {
            ModeRow(p, edit, "classic", R.string.scheduleClassic, R.string.scheduleClassicDescription)
            RowDivider(inset = false)
            ModeRow(p, edit, "alternating", R.string.scheduleAlternating, R.string.scheduleAlternatingDescription)
            RowDivider(inset = false)
            ModeRow(p, edit, "rotation", R.string.scheduleRotation, R.string.scheduleRotationDescription)
            RowDivider(inset = false)
            ModeRow(p, edit, "off", R.string.scheduleOff, R.string.scheduleOffDescription)
        }
    }
}

@Composable
private fun ModeRow(p: SyncedPreferences, edit: ((SyncedPreferences) -> SyncedPreferences) -> Unit, mode: String, title: Int, description: Int) {
    ChoiceRow(stringResource(title), p.scheduleMode == mode, { edit { it.copy(scheduleMode = mode) } }, supporting = stringResource(description))
}

@Composable
private fun TimeRow(title: String, minutes: Int, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title) },
        trailingContent = { Text(formatClock(minutes), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable(role = Role.Button, onClick = onClick),
    )
}

@Composable
private fun RemindersPage(p: SyncedPreferences, edit: ((SyncedPreferences) -> SyncedPreferences) -> Unit, ongoingEnabled: Boolean, onOngoing: (Boolean) -> Unit, onBack: (() -> Unit)?, onContinue: () -> Unit) {
    val pickTime = rememberTimePicker()
    SetupScaffold(stringResource(R.string.onboardingRemindersTitle), stringResource(R.string.onboardingRemindersBody), onBack, stringResource(R.string.continue_), onContinue,
        hero = { SetupHeroIcon(Icons.Outlined.NotificationsActive) }) {
        SettingsGroup(footer = if (p.lunchEnabled) stringResource(R.string.onboardingLunchNotifyHint) else null) {
            SwitchRow(stringResource(R.string.lunchBreak), p.lunchEnabled, { on -> edit { it.copy(lunchEnabled = on) } })
            if (p.lunchEnabled) {
                RowDivider(inset = false)
                TimeRow(stringResource(R.string.lunchStartTime), p.lunchStartMinutes) { pickTime(p.lunchStartMinutes) { m -> edit { it.copy(lunchStartMinutes = m) } } }
                RowDivider(inset = false)
                BoxWithConstraints(Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.s)) {
                    if (maxWidth < 340.dp || LocalDensity.current.fontScale >= 1.5f) {
                        Column(Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.lunchDuration), style = MaterialTheme.typography.bodyLarge)
                            DurationStepper(p, edit, Modifier.align(Alignment.End))
                        }
                    } else {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text(stringResource(R.string.lunchDuration), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                            DurationStepper(p, edit)
                        }
                    }
                }
            }
        }
        SettingsGroup(footer = stringResource(R.string.onboardingRemindersMoreInSettings)) {
            SwitchRow(stringResource(R.string.shiftReminders), p.notificationMode != "off", { on -> edit { it.copy(notificationMode = if (on) "simple" else "off") } })
            RowDivider(inset = false)
            SwitchRow(stringResource(R.string.microBreakReminder), p.microBreakEnabled, { on -> edit { it.copy(microBreakEnabled = on) } })
            RowDivider(inset = false)
            SwitchRow(stringResource(R.string.ongoingShowBeforeClockOff), ongoingEnabled, onOngoing)
        }
    }
}

@Composable
private fun DurationStepper(p: SyncedPreferences, edit: ((SyncedPreferences) -> SyncedPreferences) -> Unit, modifier: Modifier = Modifier) {
    val fiveMinutes = Strings.minutesShort(LocalResources.current, "5")
    val label = stringResource(R.string.lunchDuration)
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { edit { it.copy(lunchDurationMinutes = (it.lunchDurationMinutes - 5).coerceAtLeast(5)) } }, enabled = p.lunchDurationMinutes > 5) {
            Icon(Icons.Outlined.Remove, contentDescription = "$label − $fiveMinutes")
        }
        Text(Strings.minutesShort(LocalResources.current, p.lunchDurationMinutes.toString()), style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"))
        IconButton(onClick = { edit { it.copy(lunchDurationMinutes = (it.lunchDurationMinutes + 5).coerceAtMost(240)) } }, enabled = p.lunchDurationMinutes < 240) {
            Icon(Icons.Outlined.Add, contentDescription = "$label + $fiveMinutes")
        }
    }
}

@Composable
private fun PrivacyPage(onBack: (() -> Unit)?, onContinue: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val motion = LocalDoneAtMotion.current
    val locale = LocalConfiguration.current.locales[0]
    val exampleAmount = remember(locale) { NumberFormat.getIntegerInstance(locale).format(12345) }
    var locked by remember { mutableStateOf(false) }
    var authenticating by remember { mutableStateOf(false) }
    val reason = stringResource(R.string.unlockSalaryReason)
    LaunchedEffect(Unit) {
        delay(if (motion.reduced) 0L else DoneAtMotion.ONBOARDING_PRIVACY_DEMO_MS.toLong())
        locked = true
    }
    SetupScaffold(
        stringResource(R.string.onboardingPrivacyTitle), stringResource(R.string.onboardingPrivacyBodyLocal), onBack,
        Strings.onboardingEnableBiometrics(LocalResources.current, stringResource(R.string.biometrics)),
        onContinue = {
            if (!authenticating) {
                authenticating = true
                scope.launch {
                    // As on iOS, try the system prompt while its purpose is explained.
                    // Setup can continue after a refusal or on a device without a screen lock.
                    EarningsGate.confirmOwner(context, reason)
                    authenticating = false
                    onContinue()
                }
            }
        },
        hero = { SetupHeroIcon(Icons.Outlined.Security) },
        secondaryAction = {
            TextButton(onClick = onContinue, enabled = !authenticating, modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = DoneAtSpacing.s)) {
                Text(stringResource(R.string.notNow))
            }
        },
    ) {
        SettingsGroup {
            Column(Modifier.fillMaxWidth().padding(DoneAtSpacing.l), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
                    Text(stringResource(R.string.salarySettings), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                    AnimatedContent(locked, transitionSpec = {
                        fadeIn(tween(DoneAtMotion.STATE_ENTER_MS, easing = motion.emphasizedDecelerate)) togetherWith
                            fadeOut(tween(DoneAtMotion.STATE_EXIT_MS, easing = motion.emphasizedDecelerate))
                    }, label = "salaryPrivacyDemo") { isLocked ->
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                            Text(if (isLocked) "••••" else exampleAmount, style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"), fontWeight = FontWeight.SemiBold)
                            Icon(if (isLocked) Icons.Outlined.Lock else Icons.Outlined.LockOpen, contentDescription = if (isLocked) stringResource(R.string.salaryLocked) else stringResource(R.string.unlockSalary), tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
                Text(Strings.onboardingSalaryLockBody(LocalResources.current, stringResource(R.string.biometrics)), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        SettingsFooter(stringResource(R.string.notificationPrivacyNote))
    }
}

@Composable
private fun FinalePage(onBack: (() -> Unit)?, onFinish: () -> Unit) {
    SetupScaffold(
        stringResource(R.string.app_name), stringResource(R.string.onboardingFinaleMessage), onBack, stringResource(R.string.onboardingStartExperience), onFinish,
        hero = {
            CelebratingBrandMark(stringResource(R.string.app_name), Modifier.size(216.dp))
        },
    ) {}
}

/** A picker launcher that keeps the same DoneAt dialog for every time field. */
@Composable
fun rememberTimePicker(): (Int, (Int) -> Unit) -> Unit {
    var request by remember { mutableStateOf<Pair<Int, (Int) -> Unit>?>(null) }
    request?.let { (minutes, onPicked) ->
        DoneAtTimePicker(minutes, onDismiss = { request = null }) { picked ->
            request = null
            onPicked(picked)
        }
    }
    return { minutes, onPicked -> request = minutes to onPicked }
}

@Composable
private fun DoneAtTimePicker(minutes: Int, onDismiss: () -> Unit, onPicked: (Int) -> Unit) {
    val context = LocalContext.current
    val hoursLabel = stringResource(R.string.recordsSectionHours)
    val minutesLabel = stringResource(R.string.minutesUnit)
    val is24Hour = DateFormat.is24HourFormat(context)
    val locale = LocalConfiguration.current.locales[0]
    val periodNames = remember(locale) { DateFormatSymbols.getInstance(locale).amPmStrings }
    var hour by remember(minutes, is24Hour) {
        val value = (if (is24Hour) minutes / 60 else (minutes / 60 % 12).let { if (it == 0) 12 else it }).toString().padStart(2, '0')
        mutableStateOf(TextFieldValue(value))
    }
    var minute by remember(minutes) { mutableStateOf(TextFieldValue((minutes % 60).toString().padStart(2, '0'))) }
    var pm by remember(minutes) { mutableStateOf(minutes / 60 >= 12) }
    val hourNumber = NumberInput.committedText(hour.text, decimal = false, maxDigits = 2)?.toIntOrNull()
    val minuteNumber = NumberInput.committedText(minute.text, decimal = false, maxDigits = 2)?.toIntOrNull()
    val valid = hourNumber != null && hourNumber in (if (is24Hour) 0..23 else 1..12) && minuteNumber != null && minuteNumber in 0..59
    AlertDialog(
        onDismissRequest = onDismiss,
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xl), horizontalAlignment = Alignment.CenterHorizontally) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
                    OutlinedTextField(
                        hour, { value ->
                            val digits = NumberInput.draft(value.text, decimal = false, maxDigits = 2)
                            hour = TextFieldValue(digits, selection = TextRange(digits.length))
                        }, Modifier.weight(1f).onFocusChanged { if (it.isFocused) hour = hour.copy(selection = TextRange(0, hour.text.length)) }
                            .semantics { contentDescription = hoursLabel },
                        label = { Text(stringResource(R.string.recordsSectionHours), maxLines = 1) }, isError = hour.text.isNotEmpty() && (hourNumber == null || hourNumber !in (if (is24Hour) 0..23 else 1..12)),
                        singleLine = true, textStyle = MaterialTheme.typography.headlineMedium.copy(textAlign = TextAlign.Center),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    )
                    Text(":", style = MaterialTheme.typography.headlineMedium)
                    OutlinedTextField(
                        minute, { value ->
                            val digits = NumberInput.draft(value.text, decimal = false, maxDigits = 2)
                            minute = TextFieldValue(digits, selection = TextRange(digits.length))
                        }, Modifier.weight(1f).onFocusChanged { if (it.isFocused) minute = minute.copy(selection = TextRange(0, minute.text.length)) }
                            .semantics { contentDescription = minutesLabel },
                        label = { Text(stringResource(R.string.minutesUnit), maxLines = 1) }, isError = minute.text.isNotEmpty() && (minuteNumber == null || minuteNumber !in 0..59),
                        singleLine = true, textStyle = MaterialTheme.typography.headlineMedium.copy(textAlign = TextAlign.Center),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    )
                }
                if (!is24Hour) {
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        listOf(false, true).forEachIndexed { index, isPm ->
                            SegmentedButton(pm == isPm, { pm = isPm }, shape = SegmentedButtonDefaults.itemShape(index, 2)) {
                                Text(periodNames[index])
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val pickedHour = if (is24Hour) hourNumber!! else (hourNumber!! % 12) + if (pm) 12 else 0
                onPicked(pickedHour * 60 + minuteNumber!!)
            }, enabled = valid) { Text(stringResource(R.string.done)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

/** Whether the app is drawing dark right now (its own theme choice, not only the system's). */
@Composable
fun appIsDark() = MaterialTheme.colorScheme.surface.luminance() < 0.5f

@Composable
private fun formatClock(minutes: Int): String {
    val locale = LocalConfiguration.current.locales[0]
    return LocalTime.of(minutes / 60, minutes % 60).format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale))
}
