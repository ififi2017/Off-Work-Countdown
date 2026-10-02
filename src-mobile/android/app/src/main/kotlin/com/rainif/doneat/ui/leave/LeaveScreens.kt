package com.rainif.doneat.ui.leave

import android.app.DatePickerDialog
import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.EventAvailable
import androidx.compose.material.icons.outlined.Flight
import androidx.compose.material.icons.outlined.Luggage
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.data.WriteResult
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.leave.LeaveAdoption
import com.rainif.doneat.core.domain.leave.LeavePlannerSchedule
import com.rainif.doneat.core.domain.records.LeaveBalance
import com.rainif.doneat.core.domain.records.LeaveDay
import com.rainif.doneat.core.domain.salary.NumberInput
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.components.ActionRow
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.NavigationRow
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.components.SwitchRow
import com.rainif.doneat.ui.onboarding.appIsDark
import com.rainif.doneat.ui.settings.NumberField
import com.rainif.doneat.ui.timer.Haptics
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId

// Plan 020 §2: leave balances, the planner's way in and adopted plans (iOS `LeaveViews`).

/** Balances and adopted plans. Settings and Records both open it; Back names where. */
@Composable
fun LeaveScreen(graph: AppGraph, fromRecords: Boolean, open: (Route) -> Unit, onBack: () -> Unit) {
    val text = rememberLeaveText(graph)
    val records by graph.records.state.collectAsStateWithLifecycle()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val plus by graph.plus.authorized.collectAsStateWithLifecycle()
    val plans = remember(records.leaveDays) { LeaveAdoption.adoptedPlans(records.leaveDays) }
    DoneAtPage(text.string(R.string.leaveTitle), onBack, text.string(if (fromRecords) R.string.recordsTitle else R.string.settings)) {
        SettingsGroup {
            NavigationRow(
                text.string(R.string.leavePlanAction), { open(Route.LeavePlanner) }, Icons.Outlined.EventAvailable,
                supporting = if (plus) null else text.trialsLeft(device.leavePlannerTrialsLeft),
            )
        }
        SettingsGroup(text.string(R.string.leaveBalancesSection)) {
            records.leaveBalances.forEach { balance ->
                NavigationRow(
                    text.balanceName(balance), { open(Route.LeaveBalanceEdit(balance.id)) }, LeaveText.kindIcon(balance.kind),
                    value = text.available(records.availableLeaveHalfDays(balance)),
                    supporting = balance.validThroughDayKey?.let(text::validUntil),
                )
                RowDivider()
            }
            ActionRow(text.string(R.string.leaveAddBalance), { open(Route.LeaveBalanceEdit(null)) }, Icons.Outlined.Add)
        }
        if (plans.isNotEmpty()) {
            SettingsGroup(text.string(R.string.leaveAdoptedPlans)) {
                plans.forEachIndexed { index, plan ->
                    if (index > 0) RowDivider()
                    NavigationRow(
                        text.planTitle(plan.days), { open(Route.LeaveAdoptedPlan(plan.id)) }, Icons.Outlined.Flight,
                        supporting = text.uses(plan.days.sumOf { it.leavePortion?.halfDays ?: 0 }),
                    )
                }
            }
        }
    }
}

// Balance editor

/** Whole or half days only, so "3.5" is 7 and "3.4" is refused. */
private fun halfDays(text: String): Int? {
    val value = NumberInput.parse(text) ?: return null
    val halves = value * 2
    if (halves != Math.rint(halves) || halves > LeaveBalance.MAXIMUM_HALF_DAYS) return null
    return halves.toInt()
}

private fun halfDaysText(halfDays: Int) = if (halfDays % 2 == 0) (halfDays / 2).toString() else (halfDays / 2.0).toString()

/**
 * One balance: its kind, what it holds, what was already used outside the
 * app, and the days it may be spent on. A balance adopted leave still draws on
 * cannot be removed. [guided] is Records asking for the first balance.
 */
@Composable
fun LeaveBalanceEditScreen(graph: AppGraph, balanceID: String?, guided: Boolean, onBack: () -> Unit, onSaved: () -> Unit) {
    val text = rememberLeaveText(graph)
    val records by graph.records.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val context = LocalContext.current
    val dark = appIsDark()
    val today = remember { graph.leaveToday() }
    val existing = remember(balanceID) { balanceID?.let { id -> graph.records.state.value.leaveBalances.firstOrNull { it.id == id } } }
    val id = rememberSaveable { existing?.id ?: graph.newId() }
    var kind by rememberSaveable { mutableStateOf(existing?.kind?.let(LeaveBalance::normalizedKind) ?: "annual") }
    var name by rememberSaveable { mutableStateOf(existing?.name.orEmpty()) }
    var entitled by rememberSaveable { mutableStateOf(halfDaysText(existing?.entitledHalfDays ?: 10)) }
    var used by rememberSaveable { mutableStateOf(halfDaysText(existing?.usedHalfDays ?: 0)) }
    var hasStart by rememberSaveable { mutableStateOf(existing?.validFromDayKey != null) }
    var hasEnd by rememberSaveable { mutableStateOf(existing?.validThroughDayKey != null) }
    var start by rememberSaveable { mutableStateOf(existing?.validFromDayKey?.let(ExtendedScheduleResolver::dayNumber) ?: LeavePlannerSchedule.dayNumber(today)) }
    var end by rememberSaveable { mutableStateOf(existing?.validThroughDayKey?.let(ExtendedScheduleResolver::dayNumber) ?: LeavePlannerSchedule.dayNumber(today.plusYears(1))) }
    var saving by remember { mutableStateOf(false) }
    val isNew = existing == null
    val isInUse = !isNew && LeaveAdoption.isInUse(records, id)

    val amountsValid = halfDays(entitled) != null && halfDays(used) != null
    val result: LeaveBalance? = run {
        val entitledHalves = halfDays(entitled) ?: return@run null
        val usedHalves = halfDays(used) ?: return@run null
        val draft = LeaveBalance(
            id = id,
            kind = kind,
            name = if (kind == LeaveBalance.CUSTOM) name.trim() else null,
            entitledHalfDays = entitledHalves,
            usedHalfDays = usedHalves,
            validFromDayKey = if (hasStart) ExtendedScheduleResolver.dayKey(start) else null,
            validThroughDayKey = if (hasEnd) ExtendedScheduleResolver.dayKey(end) else null,
            editedAtMs = existing?.editedAtMs ?: 0.0,
            editCount = existing?.editCount ?: 0,
            editTieBreaker = existing?.editTieBreaker.orEmpty(),
        )
        draft.takeIf { it.isValid }
    }

    fun save() {
        val balance = result ?: return
        if (saving) return
        saving = true
        scope.launch {
            val now = graph.nowMs()
            val written = graph.records.update { state -> LeaveAdoption.upsertBalance(state, balance, now, graph.newId) to Unit }
            saving = false
            if (written is WriteResult.Saved) {
                Haptics.confirm(view)
                onSaved()
            }
        }
    }

    fun delete() {
        scope.launch {
            val now = graph.nowMs()
            if (graph.records.update { state -> LeaveAdoption.deleteBalance(state, id, now) to Unit } is WriteResult.Saved) onBack()
        }
    }

    val title = when {
        guided -> R.string.leaveSetupTitle
        isNew -> R.string.leaveNewBalance
        else -> R.string.leaveEditBalance
    }
    DoneAtPage(
        text.string(title), onBack, text.string(R.string.cancelAction),
        actions = {
            TextButton(onClick = { save() }, enabled = result != null && !saving) {
                Text(text.string(R.string.saveAction), fontWeight = FontWeight.SemiBold)
            }
        },
    ) {
        if (guided) {
            SettingsGroup {
                Row(
                    Modifier.fillMaxWidth().padding(DoneAtSpacing.l),
                    horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Outlined.Luggage, null, tint = MaterialTheme.colorScheme.primary)
                    Text(text.string(R.string.leaveSetupIntro), style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
        Column(Modifier.padding(horizontal = DoneAtSpacing.page), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            val kinds = listOf("annual", "compensatory", LeaveBalance.CUSTOM)
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                kinds.forEachIndexed { index, option ->
                    SegmentedButton(kind == option, { kind = option }, SegmentedButtonDefaults.itemShape(index, kinds.size)) {
                        Text(text.string(LeaveText.kindTitle(option)), maxLines = 1)
                    }
                }
            }
            if (kind == LeaveBalance.CUSTOM) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it.take(LeaveBalance.MAXIMUM_NAME_LENGTH) },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text(text.string(R.string.leaveBalanceNamePlaceholder)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                )
            }
        }
        SettingsGroup(footer = if (amountsValid) text.string(R.string.leaveUsedBeforeNote) else null) {
            AmountRow(text.string(R.string.leaveEntitled), entitled, text) { entitled = it }
            RowDivider(inset = false)
            AmountRow(text.string(R.string.leaveUsedBefore), used, text) { used = it }
        }
        if (!amountsValid) {
            Row(
                Modifier.padding(horizontal = DoneAtSpacing.page + DoneAtSpacing.l),
                horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Outlined.ErrorOutline, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.error)
                Text(text.string(R.string.leaveHalfDayInvalid), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }
        }
        SettingsGroup {
            SwitchRow(text.string(R.string.leaveValidFrom), hasStart, { hasStart = it })
            if (hasStart) {
                DateRow(text.fullDate(start)) {
                    showLeaveDatePicker(context, dark, start, lower = null, upper = null) { start = it; if (hasEnd && end < it) end = it }
                }
            }
            RowDivider(inset = false)
            SwitchRow(text.string(R.string.leaveValidUntil), hasEnd, { hasEnd = it })
            if (hasEnd) {
                DateRow(text.fullDate(end)) {
                    showLeaveDatePicker(context, dark, end, lower = if (hasStart) start else null, upper = null) { end = it }
                }
            }
        }
        if (!isNew) {
            SettingsGroup(footer = if (isInUse) text.string(R.string.leaveBalanceInUse) else null) {
                DestructiveRow(text.string(R.string.leaveDeleteBalance), enabled = !isInUse) { delete() }
            }
        }
    }
}

@Composable
private fun AmountRow(title: String, value: String, text: LeaveText, onChange: (String) -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = DoneAtSpacing.l, end = DoneAtSpacing.l),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        NumberField(value, onChange, decimal = true, maxDigits = 4)
        Text(text.string(R.string.leaveDaysUnit), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** A chosen date under its switch, tapped to change it. */
@Composable
private fun DateRow(value: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = DoneAtSpacing.minTouch).clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = DoneAtSpacing.l),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(value, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary)
    }
}

@Composable
internal fun DestructiveRow(title: String, enabled: Boolean = true, onClick: () -> Unit) {
    ListItem(
        headlineContent = {
            Text(title, color = if (enabled) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f))
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable(enabled = enabled, role = Role.Button, onClick = onClick),
    )
}

/** The framework date picker in DoneAt colours, as the Life editor shows it. Reads and returns civil day numbers. */
internal fun showLeaveDatePicker(context: Context, dark: Boolean, value: Int, lower: Int?, upper: Int?, onPicked: (Int) -> Unit) {
    val theme = if (dark) R.style.DoneAt_DatePickerDialog_Dark else R.style.DoneAt_DatePickerDialog_Light
    val date = LeavePlannerSchedule.date(value)
    val dialog = DatePickerDialog(context, theme, { _, y, m, d -> onPicked(LeavePlannerSchedule.dayNumber(LocalDate.of(y, m + 1, d))) },
        date.year, date.monthValue - 1, date.dayOfMonth)
    // The picker reads its limits as instants in the device zone.
    val zone = ZoneId.systemDefault()
    fun instant(day: Int) = LeavePlannerSchedule.date(day).atStartOfDay(zone).toInstant().toEpochMilli()
    upper?.let { dialog.datePicker.maxDate = instant(it) }
    lower?.let { dialog.datePicker.minDate = instant(it) }
    dialog.show()
}

// Adopted plan

/**
 * One adopted plan's days. A day can be handed back on its own; the rest of
 * the plan keeps its id, so undoing it later still finds them.
 */
@Composable
fun AdoptedLeavePlanScreen(graph: AppGraph, planID: String, onBack: () -> Unit) {
    val text = rememberLeaveText(graph)
    val records by graph.records.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val days = remember(records.leaveDays, planID) { LeaveAdoption.adoptedPlans(records.leaveDays).firstOrNull { it.id == planID }?.days.orEmpty() }
    var cancelling by rememberSaveable { mutableStateOf<String?>(null) }
    var confirmsUndo by rememberSaveable { mutableStateOf(false) }
    // The last day handed back, or the plan undone elsewhere, leaves nothing to show.
    LaunchedEffect(days.isEmpty()) { if (days.isEmpty()) onBack() }

    fun write(change: (com.rainif.doneat.core.domain.records.RecordState, Double) -> com.rainif.doneat.core.domain.records.RecordState) {
        scope.launch {
            val now = graph.nowMs()
            graph.records.update { state -> change(state, now) to Unit }
        }
    }

    DoneAtPage(text.planTitle(days), onBack, text.string(R.string.leaveTitle)) {
        SettingsGroup(footer = text.uses(days.sumOf { it.leavePortion?.halfDays ?: 0 })) {
            days.forEachIndexed { index, day ->
                if (index > 0) RowDivider(inset = false)
                AdoptedDayRow(day, records.leaveBalances, text) { cancelling = day.dayKey }
            }
        }
        SettingsGroup {
            DestructiveRow(text.string(R.string.leaveUndoPlan)) { confirmsUndo = true }
        }
    }

    cancelling?.let { key ->
        AlertDialog(
            onDismissRequest = { cancelling = null },
            title = { Text(text.string(R.string.leaveCancelDay)) },
            text = { Text(text.day(key) + "\n" + text.string(R.string.leaveCancelDayConfirm)) },
            confirmButton = {
                TextButton(onClick = {
                    cancelling = null
                    write { state, now -> LeaveAdoption.cancelDay(state, key, now) }
                }) { Text(text.string(R.string.leaveCancelDay), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { cancelling = null }) { Text(text.string(R.string.cancelAction)) } },
        )
    }
    if (confirmsUndo) {
        AlertDialog(
            onDismissRequest = { confirmsUndo = false },
            title = { Text(text.string(R.string.leaveUndoPlan)) },
            text = { Text(text.string(R.string.leaveUndoConfirm)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmsUndo = false
                    write { state, now -> LeaveAdoption.undoPlan(state, planID, now) }
                }) { Text(text.string(R.string.leaveUndoPlan), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmsUndo = false }) { Text(text.string(R.string.cancelAction)) } },
        )
    }
}

@Composable
private fun AdoptedDayRow(day: LeaveDay, balances: List<LeaveBalance>, text: LeaveText, onCancel: () -> Unit) {
    val uses = day.uses.mapNotNull { use ->
        balances.firstOrNull { it.id == use.balanceID }?.let { "${text.balanceName(it)} ${text.halfDays(use.halfDays)}" }
    }.joinToString(", ").takeIf { it.isNotEmpty() }
    val action = text.string(R.string.leaveCancelDay)
    ListItem(
        headlineContent = { Text(text.day(day.dayKey)) },
        supportingContent = uses?.let { { Text(it) } },
        trailingContent = day.leavePortion?.let { { Text(text.portion(it), style = MaterialTheme.typography.bodyMedium) } },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable(role = Role.Button, onClick = onCancel).semantics { onClick(label = action) { onCancel(); true } },
    )
}
