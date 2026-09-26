package com.rainif.doneat.ui.settings

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtPrimaryButton
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.salary.NumberInput
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.components.SettingsFooter
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.components.SwitchRow
import com.rainif.doneat.ui.timer.EarningsGate
import com.rainif.doneat.ui.timer.TimerText
import kotlinx.coroutines.launch
import java.util.Locale

/**
 * Salary (iOS `SalaryDesignView`). The one page worth shoulder-surfing, so it
 * renders nothing until the device owner confirms it is them, and locks again
 * whenever the app leaves the screen. A device with no screen lock passes
 * straight through, as on iOS.
 *
 * The amount stays the text the user typed, folded to ASCII digits and one
 * `.` ([NumberInput]); empty is "no salary", never 0.
 */
@Composable
fun SalaryScreen(graph: AppGraph, onBack: () -> Unit) {
    val context = LocalContext.current
    var unlocked by rememberSaveable { mutableStateOf(false) }
    // Bumped when the page leaves the screen, so an unlock that resolves afterwards knows it was overtaken.
    var lockGeneration by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val reason = stringResource(R.string.unlockSalaryReason)

    fun unlock() {
        if (unlocked) return
        val generation = lockGeneration
        scope.launch {
            val result = EarningsGate.confirmOwner(context, reason)
            if (generation == lockGeneration && result != EarningsGate.Result.REFUSED) unlocked = true
        }
    }

    LaunchedEffect(Unit) { unlock() }
    // Not on pause: the device-credential screen pauses this activity mid-unlock.
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) {
        unlocked = false
        lockGeneration++
    }
    // Android 13+: the recents thumbnail never shows this page.
    DisposableEffect(Unit) {
        val activity = context as? Activity ?: generateSequence(context) { (it as? android.content.ContextWrapper)?.baseContext }.filterIsInstance<Activity>().firstOrNull()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) activity?.setRecentsScreenshotEnabled(false)
        onDispose { if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) activity?.setRecentsScreenshotEnabled(true) }
    }

    if (unlocked) SalaryContent(graph, onBack) else SalaryLocked(onBack, ::unlock)
}

@Composable
private fun SalaryLocked(onBack: () -> Unit, onUnlock: () -> Unit) {
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.safeDrawingPadding().fillMaxSize()) {
            IconButton(onClick = onBack, modifier = Modifier.padding(DoneAtSpacing.xs)) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.settings))
            }
            Column(
                Modifier.weight(1f).fillMaxWidth().padding(horizontal = DoneAtSpacing.xl),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(Icons.Outlined.Lock, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(stringResource(R.string.salaryLocked), Modifier.padding(top = DoneAtSpacing.l), style = MaterialTheme.typography.titleLarge)
                Text(
                    stringResource(R.string.unlockSalaryReason), Modifier.padding(top = DoneAtSpacing.xs),
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center,
                )
            }
            DoneAtPrimaryButton(stringResource(R.string.unlockSalary), onUnlock, Modifier.fillMaxWidth().padding(DoneAtSpacing.page))
        }
    }
}

@Composable
private fun SalaryContent(graph: AppGraph, onBack: () -> Unit) {
    val prefs by graph.settings.preferences.collectAsStateWithLifecycle()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val session by graph.sessions.session.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    val context = LocalContext.current
    val text = TimerText(LocalResources.current, LocalConfiguration.current.locales[0], android.text.format.DateFormat.is24HourFormat(context), device.hideEarnings)

    // Drafts follow the committed values until the user types; a commit only sends what changed.
    var amount by remember(prefs.salaryAmount) { mutableStateOf(prefs.salaryAmount) }
    var bonus by remember(prefs.annualBonusMonths) { mutableStateOf(formatMonths(prefs.annualBonusMonths)) }
    fun commit() {
        val newAmount = amount.trim().takeIf { it != prefs.salaryAmount }
        val newBonus = NumberInput.parse(bonus)?.takeIf { it != prefs.annualBonusMonths }
        if (newAmount == null && newBonus == null) return
        scope.launch {
            graph.settings.edit { p -> p.copy(salaryAmount = newAmount ?: p.salaryAmount, annualBonusMonths = newBonus ?: p.annualBonusMonths) }
        }
    }
    DisposableEffect(Unit) { onDispose { commit() } }
    fun edit(change: (com.rainif.doneat.core.domain.records.SyncedPreferences) -> com.rainif.doneat.core.domain.records.SyncedPreferences) =
        scope.launch { graph.settings.edit(change) }

    DoneAtPage(stringResource(R.string.salarySettings), onBack, stringResource(R.string.settings)) {
        SettingsGroup {
            SwitchRow(stringResource(R.string.enableSalary), prefs.salaryEnabled, { on -> edit { it.copy(salaryEnabled = on) } }, supporting = stringResource(R.string.enableSalaryDescriptionLocal))
        }
        if (prefs.salaryEnabled) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.page)) {
                listOf("monthly" to R.string.monthly, "daily" to R.string.daily).forEachIndexed { index, (raw, label) ->
                    SegmentedButton(
                        selected = prefs.salaryType == raw,
                        onClick = { edit { it.copy(salaryType = raw) } },
                        shape = SegmentedButtonDefaults.itemShape(index, 2),
                    ) { Text(stringResource(label)) }
                }
            }
            SettingsGroup {
                FieldRow(stringResource(R.string.amount)) {
                    if (device.hideEarnings) {
                        Text(TimerText.MASK, style = MaterialTheme.typography.titleMedium)
                        // This page already confirmed the owner; revealing here needs no second check.
                        IconButton(onClick = { scope.launch { graph.settings.updateDevice { it.copy(hideEarnings = false) } } }) {
                            Icon(Icons.Outlined.Visibility, stringResource(R.string.unlockSalary))
                        }
                    } else {
                        NumberField(amount, { amount = NumberInput.sanitize(it, decimal = true, maxDigits = 9) }, emphasized = true, onCommit = { commit(); focus.clearFocus() })
                    }
                }
                if (prefs.salaryType == "monthly") {
                    RowDivider()
                    var open by remember { mutableStateOf(false) }
                    Box {
                        com.rainif.doneat.ui.components.NavigationRow(
                            stringResource(R.string.monthlyWorkingDays), { open = true }, value = text.count(prefs.monthlyWorkingDays.toInt()),
                        )
                        DropdownMenu(open, { open = false }) {
                            (15..31).forEach { days ->
                                DropdownMenuItem(text = { Text(text.count(days)) }, onClick = {
                                    open = false
                                    edit { it.copy(monthlyWorkingDays = days.toDouble()) }
                                })
                            }
                        }
                    }
                }
                RowDivider()
                SwitchRow(stringResource(R.string.annualBonus), prefs.annualBonusEnabled, { on -> edit { it.copy(annualBonusEnabled = on) } })
                if (prefs.annualBonusEnabled) {
                    RowDivider()
                    FieldRow(stringResource(R.string.annualBonusMonths)) {
                        NumberField(bonus, { bonus = NumberInput.sanitize(it, decimal = true, maxDigits = 5) }, onCommit = { commit(); focus.clearFocus() })
                    }
                }
                RowDivider()
                SwitchRow(stringResource(R.string.hideSalary), device.hideEarnings, { on -> scope.launch { graph.settings.updateDevice { it.copy(hideEarnings = on) } } })
            }
            SettingsFooter(stringResource(R.string.salaryPrivacyNoteLocal))

            val now = System.currentTimeMillis().toDouble()
            val shift = session.snapshot(now)
            val daily = shift?.dailySalary
            val earned = if (shift != null && daily != null) daily * shift.payRatio else null
            val hourly = if (shift != null && daily != null && shift.plannedDurationMs > 0) daily / (shift.plannedDurationMs / 3_600_000) else null
            Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow, modifier = Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.page)) {
                Column(Modifier.padding(DoneAtSpacing.l)) {
                    Text(stringResource(R.string.moneyEarned), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(text.money(earned), style = MaterialTheme.typography.headlineLarge.copy(fontFeatureSettings = "tnum"), fontWeight = FontWeight.Bold)
                }
            }
            SettingsGroup(title = stringResource(R.string.derivedFromThis), footer = shift?.let { "${text.relativeDuration(it.plannedDurationMs)} · ${stringResource(R.string.lunchPauseNoteNoSalary)}" } ?: stringResource(R.string.lunchPauseNoteNoSalary)) {
                com.rainif.doneat.ui.components.ValueRow(stringResource(R.string.perWorkday), text.money(daily))
                RowDivider()
                com.rainif.doneat.ui.components.ValueRow(stringResource(R.string.perEffectiveHour), text.money(hourly))
            }
        }
        Spacer(Modifier.heightIn(min = DoneAtSpacing.l))
    }
}

@Composable
private fun FieldRow(title: String, field: @Composable () -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        if (maxWidth < 360.dp || LocalDensity.current.fontScale >= 1.3f) {
            Column(
                Modifier.fillMaxWidth().padding(start = DoneAtSpacing.l, end = DoneAtSpacing.xs, top = DoneAtSpacing.m, bottom = DoneAtSpacing.m),
                verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs),
            ) {
                Text(title, style = MaterialTheme.typography.bodyLarge)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) { field() }
            }
        } else {
            Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = DoneAtSpacing.l, end = DoneAtSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
                Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                Row(verticalAlignment = Alignment.CenterVertically) { field() }
            }
        }
    }
}

/**
 * A trailing number field: decimal keypad, commits on Done and when it loses
 * focus. Focusing selects everything, as iOS does, so typing replaces the value
 * rather than landing beside a leading 0.
 */
@Composable
internal fun NumberField(
    value: String,
    onValueChange: (String) -> Unit,
    onCommit: () -> Unit = {},
    emphasized: Boolean = false,
    placeholder: String = "0",
    decimal: Boolean = true,
) {
    var field by remember { mutableStateOf(TextFieldValue(value)) }
    if (field.text != value) field = field.copy(text = value, selection = TextRange(value.length))
    var focused by remember { mutableStateOf(false) }
    val style = (if (emphasized) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyLarge)
        .copy(fontFeatureSettings = "tnum", fontWeight = FontWeight.SemiBold, textAlign = TextAlign.End, color = MaterialTheme.colorScheme.onSurface)
    BasicTextField(
        value = field,
        onValueChange = { next ->
            field = next
            onValueChange(next.text)
        },
        modifier = Modifier
            .widthIn(min = 80.dp, max = 180.dp)
            .padding(end = DoneAtSpacing.m)
            .onFocusChanged {
                if (it.isFocused && !focused) field = field.copy(selection = TextRange(0, field.text.length))
                if (focused && !it.isFocused) onCommit()
                focused = it.isFocused
            },
        textStyle = style,
        singleLine = true,
        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
        keyboardOptions = KeyboardOptions(keyboardType = if (decimal) KeyboardType.Decimal else KeyboardType.Number, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { onCommit() }),
        decorationBox = { inner ->
            Box(contentAlignment = Alignment.CenterEnd) {
                if (value.isEmpty()) Text(placeholder, style = style.copy(color = MaterialTheme.colorScheme.onSurfaceVariant))
                inner()
            }
        },
    )
}

private fun formatMonths(value: Double): String =
    if (value == Math.rint(value)) value.toLong().toString() else String.format(Locale.ROOT, "%.2f", value).trimEnd('0').trimEnd('.')
