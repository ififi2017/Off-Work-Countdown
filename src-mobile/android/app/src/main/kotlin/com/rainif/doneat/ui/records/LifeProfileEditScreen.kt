package com.rainif.doneat.ui.records

import android.app.DatePickerDialog
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ArrowDropDown
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.data.WriteResult
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.records.LifeProfileDraft
import com.rainif.doneat.core.domain.records.LifeProfiles
import com.rainif.doneat.core.domain.records.LifeSalaryCadence
import com.rainif.doneat.core.domain.records.LifeWorkHistoryMode
import com.rainif.doneat.core.domain.salary.NumberInput
import com.rainif.doneat.core.domain.summary.SummaryRules
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.PageFooter
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.onboarding.appIsDark
import com.rainif.doneat.ui.settings.NumberField
import com.rainif.doneat.ui.timer.EarningsGate
import com.rainif.doneat.ui.timer.EarningsVisibilityButton
import com.rainif.doneat.ui.timer.Haptics
import com.rainif.doneat.ui.timer.TimerText
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** Today's salary as a monthly figure, for a profile with none on file. Null while salary is hidden from the app. */
fun configuredMonthlySalary(graph: AppGraph): Double? {
    if (!graph.settings.preferences.value.salaryEnabled) return null
    return SummaryRules.salaryMonthlyEquivalent(graph.sessions.session.value.salary)
}

/** Opens the Life profile editor with a draft loaded from the archive as it stands. */
fun beginLifeEdit(graph: AppGraph, context: RecordsContext, open: (com.rainif.doneat.ui.Route) -> Unit) {
    graph.lifeEditDraft.value = LifeProfileDraft.load(context.queries.state.lifeProfile, context.today, configuredMonthlySalary(graph), graph.newId)
    open(com.rainif.doneat.ui.Route.RecordsLifeEdit)
}

/**
 * Describing a life (iOS `LifeProfileEditView`): the stage dates, how work
 * went, and how income continues. Nothing is written before Save; while
 * earnings are hidden, saving first asks for the device's owner, because the
 * profile holds salary.
 */
@Composable
fun LifeProfileEditScreen(graph: AppGraph, onBack: () -> Unit) {
    val context = rememberRecordsContext(graph)
    val text = context.text
    val res = LocalResources.current
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val android = LocalContext.current
    val dark = appIsDark()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val stored by graph.lifeEditDraft.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) {
        if (graph.lifeEditDraft.value == null) {
            graph.lifeEditDraft.value = LifeProfileDraft.load(context.queries.state.lifeProfile, context.today, configuredMonthlySalary(graph), graph.newId)
        }
    }
    val draft = stored ?: return
    fun update(change: (LifeProfileDraft) -> LifeProfileDraft) { graph.lifeEditDraft.value = graph.lifeEditDraft.value?.let(change) }
    fun leave() {
        onBack()
    }
    var saving by remember { mutableStateOf(false) }
    val ownerReason = text.string(R.string.recordsOwnerAuthReason)
    val today = context.today
    val canSave = draft.canSave(today) && !saving

    fun save() {
        if (!canSave) return
        saving = true
        scope.launch {
            if (device.hideEarnings && EarningsGate.confirmOwner(android, ownerReason) == EarningsGate.Result.REFUSED) {
                saving = false
                return@launch
            }
            val now = graph.nowMs()
            val result = graph.records.update { state ->
                LifeProfiles.edit(state, now, graph.newId) { profile -> draft.applied(profile, today) ?: profile } to Unit
            }
            saving = false
            if (result is WriteResult.Saved) {
                Haptics.confirm(view)
                leave()
            }
        }
    }

    DoneAtPage(
        text.string(R.string.lifeProfileTitle), { leave() }, text.string(R.string.recordsTitle),
        actions = {
            TextButton(onClick = { save() }, enabled = canSave) { Text(text.string(R.string.saveAction), fontWeight = FontWeight.SemiBold) }
        },
    ) {
        SettingsGroup {
            NumberRow(text.string(R.string.lifeBirthYear), draft.bornYear, "1990", 4) { v -> update { it.copy(bornYear = v) } }
            RowDivider(inset = false)
            NumberRow(text.string(R.string.lifeSchoolStarted), draft.schoolYear, suggestion(draft.bornYear, 6, text), 4) { v -> update { it.copy(schoolYear = v) } }
            RowDivider(inset = false)
            NumberRow(text.string(R.string.lifeRetirementAge), draft.retirementAge, "60", 3) { v -> update { it.copy(retirementAge = v) } }
            RowDivider(inset = false)
            NumberRow(text.string(R.string.lifeSleepHours), draft.sleepHours, "8", 4, decimal = true) { v -> update { it.copy(sleepHours = v) } }
        }

        Choice(
            text.string(R.string.lifeWorkHistoryMode),
            listOf(LifeWorkHistoryMode.ROUGH to R.string.lifeWorkHistoryRough, LifeWorkHistoryMode.DETAILED to R.string.lifeWorkHistoryDetailed),
            draft.mode, text,
        ) { mode -> update { it.copy(mode = mode) } }
        val salaryRow: @Composable (String, String, LifeSalaryCadence, (String) -> Unit, (LifeSalaryCadence) -> Unit) -> Unit = { title, amount, cadence, onAmount, onCadence ->
            SalaryRow(graph, title, amount, cadence, device.hideEarnings, text, onAmount, onCadence)
        }
        if (draft.mode == LifeWorkHistoryMode.ROUGH) {
            SettingsGroup(footer = text.string(R.string.lifeRoughIncomeHelp)) {
                NumberRow(text.string(R.string.lifeWorkStarted), draft.workYear, suggestion(draft.bornYear, 22, text), 4) { v -> update { it.copy(workYear = v) } }
                RowDivider(inset = false)
                salaryRow(text.string(R.string.lifeCurrentSalary), draft.roughAmount, draft.roughCadence, { v -> update { it.copy(roughAmount = v) } }, { c -> update { it.copy(roughCadence = c) } })
            }
        } else {
            PageFooter(text.string(R.string.lifeDetailedIncomeHelp))
            if (draft.linkedPeriods(today) == null) {
                Text(
                    text.string(R.string.lifeEmploymentValidation),
                    modifier = Modifier.padding(horizontal = DoneAtSpacing.page + DoneAtSpacing.l),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            draft.employment.forEachIndexed { index, job ->
                val current = index == 0
                SettingsGroup(title = if (current) text.string(R.string.lifeEmploymentCurrent) else null) {
                    val (lower, upper) = draft.startRange(index, today)
                    ValueRow(text.string(R.string.lifeEmploymentStart), formatDate(job.startDate, text)) {
                        showDatePicker(android, dark, job.startDate, lower, upper) { picked ->
                            update { d -> d.copy(employment = d.employment.map { if (it.id == job.id) it.copy(startDate = picked) else it }) }
                        }
                    }
                    RowDivider(inset = false)
                    ValueRow(
                        text.string(R.string.lifeEmploymentEnd),
                        draft.endDate(index)?.let { formatDate(it, text) } ?: text.string(R.string.lifeStagePresent),
                        onClick = null,
                    )
                    RowDivider(inset = false)
                    if (current) {
                        salaryRow(text.string(R.string.lifeEmploymentSalary), draft.roughAmount, draft.roughCadence, { v -> update { it.copy(roughAmount = v) } }, { c -> update { it.copy(roughCadence = c) } })
                    } else {
                        salaryRow(
                            text.string(R.string.lifeEmploymentSalary), job.amount, job.cadence,
                            { v -> update { d -> d.copy(employment = d.employment.map { if (it.id == job.id) it.copy(amount = v) else it }) } },
                            { c -> update { d -> d.copy(employment = d.employment.map { if (it.id == job.id) it.copy(cadence = c) else it }) } },
                        )
                        RowDivider(inset = false)
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 52.dp)
                                .clickable(role = Role.Button) { update { d -> d.copy(employment = d.employment.filter { it.id != job.id }) } }
                                .padding(horizontal = DoneAtSpacing.l),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.l),
                        ) {
                            Icon(Icons.Outlined.DeleteOutline, null, tint = MaterialTheme.colorScheme.error)
                            Text(text.string(R.string.lifeRemoveEmployment), color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }
            OutlinedButton(
                onClick = { update { it.addingEmployment(today, graph.newId()) } },
                modifier = Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.page),
            ) {
                Icon(Icons.Outlined.Add, null)
                Text(text.string(R.string.lifeAddEmployment), Modifier.padding(start = 8.dp))
            }
        }

        Choice(
            text.string(R.string.lifeFutureIncomeMode),
            listOf(false to R.string.lifeFutureIncomeKeep, true to R.string.lifeFutureIncomeDecline),
            draft.declines, text,
        ) { declines -> update { it.copy(declines = declines) } }
        if (draft.declines) {
            val preview = draft.incomeDecline?.let {
                Strings.lifeIncomeDeclinePreview(res, text.count(it.startsAtAge), text.percent(it.retirementRatio * 100, 0))
            }
            SettingsGroup(footer = preview) {
                NumberRow(text.string(R.string.lifeIncomeDeclineStartAge), draft.declineAge, "45", 3) { v -> update { it.copy(declineAge = v) } }
                RowDivider(inset = false)
                NumberRow(text.string(R.string.lifeIncomeRetirementRatio), draft.ratioPercent, "60", 3) { v -> update { it.copy(ratioPercent = v) } }
            }
        }
        PageFooter(text.string(R.string.lifeProfileFooterLocal))
    }
}

/** The placeholder a year field shows: birth year plus the usual age, or "suggested". */
private fun suggestion(bornYear: String, offset: Int, text: RecordsText) =
    bornYear.toIntOrNull()?.let { (it + offset).toString() } ?: text.string(R.string.lifeSuggestedYear)

private fun formatDate(date: LocalDate, text: RecordsText): String =
    DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(text.locale).format(date)

/** The framework date picker in DoneAt colours, limited to the days a job may start. */
private fun showDatePicker(context: android.content.Context, dark: Boolean, value: LocalDate, lower: LocalDate?, upper: LocalDate, onPicked: (LocalDate) -> Unit) {
    val theme = if (dark) R.style.DoneAt_DatePickerDialog_Dark else R.style.DoneAt_DatePickerDialog_Light
    val dialog = DatePickerDialog(context, theme, { _, y, m, d -> onPicked(LocalDate.of(y, m + 1, d)) }, value.year, value.monthValue - 1, value.dayOfMonth)
    // The picker reads its limits as instants in the device zone.
    val zone = ZoneId.systemDefault()
    dialog.datePicker.maxDate = upper.atStartOfDay(zone).toInstant().toEpochMilli()
    lower?.let { dialog.datePicker.minDate = it.atStartOfDay(zone).toInstant().toEpochMilli() }
    dialog.show()
}

@Composable
private fun NumberRow(title: String, value: String, placeholder: String, maxDigits: Int, decimal: Boolean = false, onChange: (String) -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = DoneAtSpacing.l).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        NumberField(value, { onChange(NumberInput.sanitize(it, decimal, maxDigits)) }, placeholder = placeholder, decimal = decimal)
    }
}

@Composable
private fun ValueRow(title: String, value: String, onClick: (() -> Unit)?) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp)
            .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .padding(horizontal = DoneAtSpacing.l),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Text(value, style = MaterialTheme.typography.bodyLarge, color = if (onClick != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** A salary and its cadence; the amount is masked, with the eye beside it, while earnings are hidden. */
@Composable
private fun SalaryRow(
    graph: AppGraph,
    title: String,
    amount: String,
    cadence: LifeSalaryCadence,
    hidden: Boolean,
    text: RecordsText,
    onAmount: (String) -> Unit,
    onCadence: (LifeSalaryCadence) -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = DoneAtSpacing.l), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        if (hidden) {
            Text(TimerText.MASK, style = MaterialTheme.typography.bodyLarge)
            EarningsVisibilityButton(graph) {}
        } else {
            NumberField(amount, { onAmount(NumberInput.sanitize(it, decimal = true, maxDigits = 12)) })
        }
        Box {
            TextButton(onClick = { menu = true }, Modifier.semantics { contentDescription = text.string(R.string.lifeSalaryCadence) }) {
                Text(text.string(if (cadence == LifeSalaryCadence.MONTHLY) R.string.lifeSalaryMonthly else R.string.lifeSalaryYearly))
                Icon(Icons.Outlined.ArrowDropDown, null)
            }
            DropdownMenu(menu, { menu = false }) {
                listOf(LifeSalaryCadence.MONTHLY to R.string.lifeSalaryMonthly, LifeSalaryCadence.YEARLY to R.string.lifeSalaryYearly).forEach { (value, label) ->
                    DropdownMenuItem({ Text(text.string(label)) }, { menu = false; onCadence(value) })
                }
            }
        }
    }
}

/** A two-way choice with its label, as iOS's segmented pickers. */
@Composable
private fun <T> Choice(label: String, options: List<Pair<T, Int>>, selected: T, text: RecordsText, onSelect: (T) -> Unit) {
    Column(Modifier.padding(horizontal = DoneAtSpacing.page), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        Text(label, Modifier.padding(start = DoneAtSpacing.l), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            options.forEachIndexed { index, (value, title) ->
                SegmentedButton(value == selected, { onSelect(value) }, SegmentedButtonDefaults.itemShape(index, options.size)) {
                    Text(text.string(title), maxLines = 1)
                }
            }
        }
    }
}
