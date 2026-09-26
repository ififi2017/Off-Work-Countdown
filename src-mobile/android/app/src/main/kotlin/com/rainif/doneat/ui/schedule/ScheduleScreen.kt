package com.rainif.doneat.ui.schedule

import android.text.format.DateFormat
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.EventBusy
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.core.graphics.toColorInt
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.records.DayRecordResolver
import com.rainif.doneat.core.domain.records.RecordHistory
import com.rainif.doneat.core.domain.schedule.CivilZone
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleContent
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleDay
import com.rainif.doneat.core.domain.schedule.ExtendedSchedulePlan
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleResolver
import com.rainif.doneat.core.domain.schedule.HolidayCalendar
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ShiftCycleRule
import com.rainif.doneat.core.domain.schedule.ShiftType
import com.rainif.doneat.core.domain.session.PlannedPreview
import com.rainif.doneat.core.domain.session.RosterDayEdit
import com.rainif.doneat.core.domain.session.ScheduleDecision
import com.rainif.doneat.core.domain.session.ScheduleEditing
import com.rainif.doneat.core.domain.session.ScheduleFieldChange
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.core.domain.session.applyingTemplate
import com.rainif.doneat.core.domain.session.extendedTodayKey
import com.rainif.doneat.core.domain.session.plannedPreview
import com.rainif.doneat.core.domain.session.protectedRosterDays
import com.rainif.doneat.core.domain.session.seededExtendedContent
import com.rainif.doneat.core.domain.session.shouldPromptApplyingToToday
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.timer.Haptics
import kotlinx.coroutines.launch
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.time.temporal.WeekFields
import java.util.Locale

/** Presentation-only modes; the saved schedule keeps its own model. iOS `ScheduleEditorMode`. */
private enum class EditorMode(val title: Int, val preset: ShiftCycleRule.Preset?) {
    WEEKLY(R.string.scheduleClassic, ShiftCycleRule.Preset.WEEKLY),
    ALTERNATING(R.string.scheduleAlternating, ShiftCycleRule.Preset.ALTERNATING_WEEKS),
    ROTATION(R.string.scheduleRotation, ShiftCycleRule.Preset.ROTATION),
    FREE(R.string.scheduleFreeCalendar, null),
    MANUAL(R.string.scheduleManualTimer, null),
}

/**
 * The schedule page (iOS `ScheduleSettingsView` + `ScheduleCalendarEditor`):
 * one month calendar over the shift types and pattern. Every edit lands in
 * the page's draft ([AppGraph.scheduleDraft]); Save commits it once and asks
 * whether today changes too when the rules say it would.
 *
 * A fixed schedule is shown as the extended one it is equivalent to, so the
 * page never has two editors; nothing is stored until Save.
 */
@Composable
fun ScheduleScreen(graph: AppGraph, open: (Route) -> Unit, onBack: () -> Unit) {
    val draft by graph.scheduleDraft.collectAsStateWithLifecycle()
    val session by graph.sessions.session.collectAsStateWithLifecycle()
    val records by graph.records.state.collectAsStateWithLifecycle()
    val res = LocalResources.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val locale = LocalConfiguration.current.locales[0]
    val now = remember { System.currentTimeMillis().toDouble() }
    val env = session.env
    val workName = stringResource(R.string.extendedDefaultWorkShift)
    val restName = stringResource(R.string.extendedDefaultRest)

    // A fixed schedule gets a stable, equivalent preview; opening the page writes nothing.
    val previewSeed = remember(env.extendedSchedule == null) { session.seededExtendedContent(draft, now, workName, restName, seedIds()) }
    val content: ExtendedScheduleContent = draft.extendedContent ?: env.extendedSchedule?.content?.takeIf { env.isExtendedScheduleEnabled } ?: previewSeed
    val isManual = !(draft.extendedScheduleEnabled ?: env.isExtendedScheduleEnabled) && (draft.scheduleMode ?: session.scheduleMode) == ScheduleMode.OFF
    val handSet = ScheduleEditing.handSetDays(env.handSetDays, draft.rosterEdits)
    val today = session.extendedTodayKey(now)
    val recordsZone = env.preferences.recordsTimeZoneIdentifier

    fun edit(change: (ScheduleFieldChange) -> ScheduleFieldChange) {
        graph.scheduleDraft.value = change(graph.scheduleDraft.value).settled(env, session.state, now)
    }
    fun updateContent(updated: ExtendedScheduleContent) {
        val next = if (updated.rule != null) updated.copy(clearedFromDayKey = null) else updated
        edit { d ->
            var c = if (next.rule != null) d.restoringPatternAfterFreePreview() else d
            c = c.copy(extendedContent = next, extendedScheduleEnabled = !isManual)
            // Manual timing keeps its hours in the fixed fields.
            ScheduleEditing.activeTypes(next).firstOrNull { it.kind == ShiftType.Kind.WORK }?.takeIf { isManual }?.let { w ->
                c = c.copy(startMinutes = w.startMinutes, endMinutes = w.endMinutes, lunchEnabled = w.breakEnabled, lunchStartMinutes = w.breakStartMinutes, lunchDurationMinutes = w.breakDurationMinutes)
            }
            c
        }
    }
    fun setManual(manual: Boolean) = edit {
        it.copy(clearExpectedFromDayKey = null, extendedContent = content, extendedScheduleEnabled = !manual, scheduleMode = if (manual) ScheduleMode.OFF else ScheduleMode.CLASSIC)
    }
    fun setDay(key: String, change: RosterDayEdit) = edit { d ->
        var edits = ScheduleEditing.editing(d.rosterEdits, key, change, env.handSetDays)
        // A generated row given the same shift by hand stops being generated.
        if (change is RosterDayEdit.Shift && key in env.generatedRosterDays) edits = edits.orEmpty() + (key to change)
        d.copy(materializedRosterDays = d.materializedRosterDays - key, extendedContent = content, extendedScheduleEnabled = !isManual, rosterEdits = edits)
    }
    fun removePattern() {
        val plan = ExtendedSchedulePlan(content.shiftTypes, content.rule, handSet, content.holidayRegionIdentifier, content.clearedFromDayKey, holidays = env.holidays)
        val months = listOf(0, 1).mapNotNull { ScheduleEditing.month(today, it) }
        val from = RecordHistory.extendedScheduleStart(records) ?: today
        // A template switch never invents career history outside an existing period.
        val kept = ScheduleEditing.keepingPattern(plan, months, from, graph.scheduleDraft.value.rosterEdits)
            ?.filterKeys { it >= today || DayRecordResolver.period(it, records.periods) != null }
        edit { d ->
            d.copy(
                extendedContent = content.copy(rule = null), extendedScheduleEnabled = true, scheduleMode = ScheduleMode.CLASSIC, rosterEdits = kept,
                materializedRosterDays = d.materializedRosterDays + (kept?.keys.orEmpty() - d.rosterEdits?.keys.orEmpty()),
            )
        }
    }
    fun clearExpected() {
        if (content.rule != null || isManual) return
        graph.scheduleDraft.value = ScheduleEditing.clearingExpectedDays(
            graph.scheduleDraft.value, content, records.rosterDays, ShiftSession.dayKey(now, session.recordsZone), session.protectedRosterDays(records, now),
        ).settled(env, session.state, now)
    }

    val mode = when {
        isManual -> EditorMode.MANUAL
        content.rule == null -> EditorMode.FREE
        content.rule!!.preset == ShiftCycleRule.Preset.WEEKLY -> EditorMode.WEEKLY
        content.rule!!.preset == ShiftCycleRule.Preset.ALTERNATING_WEEKS -> EditorMode.ALTERNATING
        else -> EditorMode.ROTATION
    }
    // Switching away and back restores the pattern the user had built, not a fresh template.
    val patternDrafts = remember { mutableStateMapOf<EditorMode, ShiftCycleRule>() }
    fun applyMode(next: EditorMode) {
        content.rule?.takeIf { !isManual }?.let { patternDrafts[mode] = it }
        if (next == EditorMode.MANUAL) { setManual(true); return }
        setManual(false)
        when {
            next == EditorMode.FREE -> removePattern()
            next.preset != null -> {
                val saved = patternDrafts[next]
                updateContent(if (saved != null) content.copy(rule = saved) else session.applyingTemplate(next.preset, content, now, restName))
            }
        }
    }

    var pendingMode by remember { mutableStateOf<EditorMode?>(null) }
    var confirmClear by remember { mutableStateOf(false) }
    var showRegions by remember { mutableStateOf(false) }
    var askToday by remember { mutableStateOf(false) }
    var askDiscard by remember { mutableStateOf(false) }
    var monthOffset by rememberSaveable { mutableIntStateOf(0) }
    var selectedKey by rememberSaveable { mutableStateOf<String?>(null) }
    val selected = selectedKey ?: today

    fun commit(decision: ScheduleDecision) {
        scope.launch {
            if (graph.sessions.applyScheduleChange(graph.scheduleDraft.value, decision, System.currentTimeMillis().toDouble())) {
                graph.scheduleDraft.value = ScheduleFieldChange()
                Haptics.confirm(view)
            }
        }
    }
    fun back() = if (draft.isEmpty) onBack() else askDiscard = true
    BackHandler(enabled = !draft.isEmpty) { askDiscard = true }

    val resolver = ExtendedScheduleResolver(
        ExtendedSchedulePlan(
            content.shiftTypes, content.rule, handSet, content.holidayRegionIdentifier, content.clearedFromDayKey,
            frozenShiftTypes = ExtendedSchedulePlan.frozenShiftTypes(records.rosterDays).filterKeys { draft.rosterEdits?.get(it) == null },
            holidays = env.holidays,
        ),
    )
    fun typeForDay(key: String, id: java.util.UUID?): ShiftType? {
        (draft.rosterEdits?.get(key) as? RosterDayEdit.Shift)?.let { edit -> return content.shiftTypes.firstOrNull { it.id == edit.id } }
        if (key < today) {
            return when (val p = plannedPreview(records, key, content.shiftTypes, draft.rosterEdits?.get(key) == RosterDayEdit.FollowPattern, env.holidays)) {
                is PlannedPreview.Shift -> p.type
                PlannedPreview.Rest -> content.shiftTypes.firstOrNull { it.kind == ShiftType.Kind.REST }
                PlannedPreview.NoPlan -> null
            }
        }
        return id?.let { i -> content.shiftTypes.firstOrNull { it.id == i } }
    }

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.safeDrawingPadding()) {
            Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = DoneAtSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { back() }) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.settings)) }
                Text(stringResource(R.string.workSchedule), Modifier.weight(1f), style = MaterialTheme.typography.titleLarge)
                TextButton(onClick = {
                    if (session.shouldPromptApplyingToToday(draft, System.currentTimeMillis().toDouble())) askToday = true else commit(ScheduleDecision.NEXT_SHIFT_ONLY)
                }, enabled = !draft.isEmpty) { Text(stringResource(R.string.saveAction), fontWeight = FontWeight.SemiBold) }
            }
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = DoneAtSpacing.page)
                    .wrapContentWidth(Alignment.CenterHorizontally).widthIn(max = 600.dp).padding(bottom = DoneAtSpacing.xl),
                verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l),
            ) {
                ScheduleEditing.month(today, monthOffset)?.let { month ->
                    MonthCalendar(
                        month, locale, today, selected, resolver, env.holidays, content, ::typeForDay,
                        onSelect = { selectedKey = it; view.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK) },
                        onMonth = { delta ->
                            monthOffset += delta
                            ScheduleEditing.month(today, monthOffset)?.let { (y, m) -> selectedKey = ExtendedScheduleResolver.dayKey(CivilZone.dayNumber(y, m, 1)) }
                        },
                        onToday = { monthOffset = 0; selectedKey = today },
                    )
                }
                Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
                    Column {
                        ModePicker(mode) { next ->
                            if (next == mode) return@ModePicker
                            if (next == EditorMode.MANUAL || mode == EditorMode.MANUAL) applyMode(next) else pendingMode = next
                        }
                        Controls(mode, content, today, locale, isManual, ::updateContent, restName) { confirmClear = true }
                        HolidayRow(content.holidayRegionIdentifier, locale) { showRegions = true }
                    }
                }
                SelectedDay(
                    selected, today, locale, content, handSet, resolver, env.holidays, ::typeForDay,
                    canEdit = selected >= today || DayRecordResolver.period(selected, records.periods) != null,
                    hoursLabel = { hoursLabel(res, it) },
                    onTypes = { open(Route.ShiftTypes) },
                    onAssign = { id -> if (handSet[selected] != id) { setDay(selected, RosterDayEdit.Shift(id)); Haptics.confirm(view) } },
                    onFollowPattern = { setDay(selected, RosterDayEdit.FollowPattern) },
                )
            }
        }
    }

    pendingMode?.let { next ->
        val free = next == EditorMode.FREE
        AlertDialog(
            onDismissRequest = { pendingMode = null },
            title = { Text(stringResource(if (free) R.string.extendedRemovePatternTitle else R.string.extendedApplyTemplateTitle)) },
            text = { Text(if (free) stringResource(R.string.extendedRemovePatternMessage) else Strings.extendedApplyTemplateMessage(res, stringResource(next.title))) },
            confirmButton = { TextButton(onClick = { pendingMode = null; applyMode(next) }) { Text(stringResource(next.title)) } },
            dismissButton = { TextButton(onClick = { pendingMode = null }) { Text(stringResource(R.string.cancelAction)) } },
        )
    }
    if (confirmClear) {
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            title = { Text(stringResource(R.string.scheduleClearExpected)) },
            text = { Text(stringResource(R.string.scheduleClearExpectedMessage)) },
            confirmButton = { TextButton(onClick = { confirmClear = false; clearExpected() }) { Text(stringResource(R.string.scheduleClearExpected), color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { confirmClear = false }) { Text(stringResource(R.string.cancelAction)) } },
        )
    }
    if (askToday) {
        AlertDialog(
            onDismissRequest = { askToday = false },
            title = { Text(stringResource(R.string.applyScheduleTitle)) },
            text = { Text(stringResource(R.string.applyScheduleMessage)) },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    TextButton(onClick = { askToday = false; commit(ScheduleDecision.NEXT_SHIFT_ONLY) }) { Text(stringResource(R.string.applyFromNextShift)) }
                    TextButton(onClick = { askToday = false; commit(ScheduleDecision.APPLY_TO_TODAY) }) { Text(stringResource(R.string.applyToToday)) }
                    TextButton(onClick = { askToday = false }) { Text(stringResource(R.string.cancelAction)) }
                }
            },
        )
    }
    if (askDiscard) {
        AlertDialog(
            onDismissRequest = { askDiscard = false },
            title = { Text(stringResource(R.string.unsavedChangesTitle)) },
            confirmButton = { TextButton(onClick = { askDiscard = false }) { Text(stringResource(R.string.keepEditing)) } },
            dismissButton = {
                TextButton(onClick = { askDiscard = false; graph.scheduleDraft.value = ScheduleFieldChange(); onBack() }) {
                    Text(stringResource(R.string.discardChanges), color = MaterialTheme.colorScheme.error)
                }
            },
        )
    }
    if (showRegions) {
        HolidayRegionPicker(env.holidays, locale, content.holidayRegionIdentifier, onDismiss = { showRegions = false }) { region ->
            showRegions = false
            if (region != content.holidayRegionIdentifier) updateContent(content.copy(holidayRegionIdentifier = region))
        }
    }
}

// Calendar

@Composable
private fun MonthCalendar(
    month: Pair<Int, Int>,
    locale: Locale,
    today: String,
    selected: String,
    resolver: ExtendedScheduleResolver,
    holidays: HolidayCalendar,
    content: ExtendedScheduleContent,
    typeForDay: (String, java.util.UUID?) -> ShiftType?,
    onSelect: (String) -> Unit,
    onMonth: (Int) -> Unit,
    onToday: () -> Unit,
) {
    val (year, monthValue) = month
    val first = LocalDate.of(year, monthValue, 1)
    val firstDay = WeekFields.of(locale).firstDayOfWeek
    val leading = Math.floorMod(first.dayOfWeek.value - firstDay.value, 7)
    val count = first.lengthOfMonth()
    val slots = ((leading + count + 6) / 7) * 7
    val firstNumber = CivilZone.dayNumber(year, monthValue, 1)
    val region = content.holidayRegionIdentifier?.takeIf { it.isNotEmpty() }
    Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.padding(DoneAtSpacing.s)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "yMMMM"), locale).format(first),
                    Modifier.weight(1f).clickable(onClickLabel = stringResource(R.string.extendedToday), onClick = onToday).padding(DoneAtSpacing.s),
                    style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                )
                IconButton(onClick = { onMonth(-1) }) { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowLeft, stringResource(R.string.extendedPreviousMonth)) }
                IconButton(onClick = { onMonth(1) }) { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, stringResource(R.string.extendedNextMonth)) }
            }
            Row {
                (0 until 7).forEach { i ->
                    Text(
                        firstDay.plus(i.toLong()).getDisplayName(TextStyle.SHORT, locale), Modifier.weight(1f),
                        style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center, maxLines = 1,
                    )
                }
            }
            (0 until slots / 7).forEach { row ->
                Row(Modifier.padding(top = DoneAtSpacing.xs)) {
                    (0 until 7).forEach { col ->
                        val slot = row * 7 + col
                        Box(Modifier.weight(1f).padding(2.dp)) {
                            if (slot in leading until leading + count) {
                                val number = firstNumber + slot - leading
                                val key = ExtendedScheduleResolver.dayKey(number)
                                val type = typeForDay(key, resolver.day(number).shiftTypeID)
                                val holiday = region?.let { holidays.day(dateCode(key), it) }
                                DayCell(slot - leading + 1, key, type, key == selected, key == today, holiday, locale, onSelect)
                            }
                        }
                    }
                }
            }
            if (region != null) {
                val warning = when {
                    !holidays.covers(year, region) -> Strings.holidayCoverageYearWarning(LocalResources.current, year.toString())
                    monthValue == 12 && !holidays.covers(year + 1, region) -> Strings.holidayCoverageNextYearWarning(LocalResources.current, (year + 1).toString())
                    else -> null
                }
                warning?.let {
                    Row(Modifier.padding(DoneAtSpacing.s), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.WarningAmber, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(it, Modifier.padding(start = DoneAtSpacing.xs), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

private fun dateCode(key: String): Int = ExtendedScheduleResolver.parse(key)!!.let { (y, m, d) -> y * 10_000 + m * 100 + d }

@Composable
private fun DayCell(day: Int, key: String, type: ShiftType?, chosen: Boolean, isToday: Boolean, holiday: HolidayCalendar.Day?, locale: Locale, onSelect: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    // This page edits plans: one uniform work colour, never an intensity that implies recorded hours.
    val fill = when (type?.kind) {
        ShiftType.Kind.WORK -> scheme.primary.copy(alpha = 0.13f)
        ShiftType.Kind.REST -> scheme.surfaceContainerHighest.copy(alpha = 0.5f)
        null -> Color.Transparent
    }
    val label = listOfNotNull(
        DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "MMMMdEEEE"), locale).format(LocalDate.parse(key)),
        type?.name, holiday?.let { holidayName(it, locale) },
        if (isToday) stringResource(R.string.extendedToday) else null,
    ).joinToString(", ")
    Column(
        Modifier.fillMaxWidth().heightIn(min = 46.dp)
            .background(fill, RoundedCornerShape(8.dp))
            .then(if (chosen) Modifier.border(2.dp, scheme.primary, RoundedCornerShape(8.dp)) else Modifier)
            // One node for TalkBack: the day's full label, its selection and the tap.
            .clearAndSetSemantics { contentDescription = label; this.selected = chosen; onClick { onSelect(key); true } }
            .clickable { onSelect(key) }
            .padding(vertical = DoneAtSpacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            java.text.NumberFormat.getIntegerInstance(locale).format(day),
            style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"),
            fontWeight = if (chosen || isToday) FontWeight.SemiBold else null,
            color = if (chosen || isToday) scheme.primary else scheme.onSurface,
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (holiday != null) Box(Modifier.padding(end = 2.dp).size(3.dp).background(if (holiday.isWorkday) scheme.primary else scheme.onSurfaceVariant, CircleShape))
            Text(type?.name ?: "–", style = MaterialTheme.typography.labelSmall, color = scheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Clip)
        }
    }
}

// Pattern

@Composable
private fun ModePicker(mode: EditorMode, onChoose: (EditorMode) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable { open = true }.padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.m),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(stringResource(R.string.extendedPattern), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(stringResource(mode.title), style = MaterialTheme.typography.bodyMedium)
            Icon(Icons.Outlined.UnfoldMore, null, Modifier.padding(start = DoneAtSpacing.s).size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        DropdownMenu(open, { open = false }) {
            EditorMode.entries.forEach { option ->
                DropdownMenuItem(
                    text = { Text(stringResource(option.title)) },
                    onClick = { open = false; onChoose(option) },
                    trailingIcon = if (option == mode) { { Icon(Icons.Outlined.Check, null) } } else null,
                )
            }
        }
    }
}

@Composable
private fun Controls(
    mode: EditorMode,
    content: ExtendedScheduleContent,
    today: String,
    locale: Locale,
    isManual: Boolean,
    onContent: (ExtendedScheduleContent) -> Unit,
    restName: String,
    onClearExpected: () -> Unit,
) {
    val res = LocalResources.current
    val rule = content.rule
    when {
        isManual -> Text(
            stringResource(R.string.scheduleOffManualStart), Modifier.padding(horizontal = DoneAtSpacing.l).padding(bottom = DoneAtSpacing.m),
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        rule != null -> Column(Modifier.padding(horizontal = DoneAtSpacing.m).padding(bottom = DoneAtSpacing.m), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
            var week by remember { mutableIntStateOf(0) }
            if (mode == EditorMode.ALTERNATING) {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    (0 until 2).forEach { i ->
                        SegmentedButton(week == i, { week = i }, SegmentedButtonDefaults.itemShape(i, 2)) { Text(Strings.extendedWeekNumber(res, (i + 1).toString())) }
                    }
                }
            } else if (mode == EditorMode.ROTATION) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("${stringResource(R.string.extendedCycleLength)}: ${rule.days.size}", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                    TextButton(onClick = { onContent(ScheduleEditing.resizing(content, rule.days.size - 1, restName)) }, enabled = rule.days.size > 1) { Text("−") }
                    TextButton(onClick = { onContent(ScheduleEditing.resizing(content, rule.days.size + 1, restName)) }, enabled = rule.days.size < ShiftCycleRule.MAXIMUM_LENGTH) { Text("+") }
                }
                var open by remember { mutableStateOf(false) }
                val current = ScheduleEditing.cycleDay(rule, today) ?: 1
                Box {
                    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable { open = true }, verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.extendedTodayIs), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(Strings.extendedCycleDay(res, current.toString()), style = MaterialTheme.typography.bodyMedium)
                        Icon(Icons.Outlined.UnfoldMore, null, Modifier.size(16.dp))
                    }
                    DropdownMenu(open, { open = false }) {
                        (1..rule.days.size).forEach { day ->
                            DropdownMenuItem(text = { Text(Strings.extendedCycleDay(res, day.toString())) }, onClick = { open = false; onContent(ScheduleEditing.anchoring(content, today, day)) })
                        }
                    }
                }
            }
            CycleGrid(mode, rule, content, if (mode == EditorMode.ALTERNATING) week * 7 else 0, locale, onContent)
        }
        else -> TextButton(onClick = onClearExpected, modifier = Modifier.padding(horizontal = DoneAtSpacing.s)) {
            Icon(Icons.Outlined.EventBusy, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.error)
            Text(stringResource(R.string.scheduleClearExpected), Modifier.padding(start = DoneAtSpacing.s), color = MaterialTheme.colorScheme.error)
        }
    }
}

@Composable
private fun CycleGrid(mode: EditorMode, rule: ShiftCycleRule, content: ExtendedScheduleContent, start: Int, locale: Locale, onContent: (ExtendedScheduleContent) -> Unit) {
    val end = if (mode == EditorMode.ALTERNATING) minOf(start + 7, rule.days.size) else rule.days.size
    val types = ScheduleEditing.activeTypes(content)
    val scheme = MaterialTheme.colorScheme
    (start until end).chunked(7).forEach { row ->
        Row {
            row.forEach { index ->
                val type = content.shiftTypes.firstOrNull { it.id == rule.days[index] }
                val work = type?.kind == ShiftType.Kind.WORK
                val label = if (mode == EditorMode.ROTATION) (index + 1).toString() else DayOfWeek.of(index % 7 + 1).getDisplayName(TextStyle.SHORT, locale)
                var open by remember { mutableStateOf(false) }
                Box(Modifier.weight(1f).padding(2.dp)) {
                    Column(
                        Modifier.fillMaxWidth().heightIn(min = 44.dp)
                            .background(if (work) scheme.primary.copy(alpha = 0.10f) else scheme.surfaceContainerHighest.copy(alpha = 0.6f), MaterialTheme.shapes.medium)
                            .clickable { open = true }
                            .semantics(mergeDescendants = true) { contentDescription = "$label, ${type?.name ?: ""}" }
                            .padding(vertical = DoneAtSpacing.xs),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                    ) {
                        Text(label, style = MaterialTheme.typography.bodyMedium, fontWeight = if (work) FontWeight.SemiBold else null, color = if (work) scheme.primary else scheme.onSurfaceVariant, maxLines = 1)
                        if (mode == EditorMode.ROTATION) Text(type?.name ?: "–", style = MaterialTheme.typography.labelSmall, color = scheme.onSurfaceVariant, maxLines = 1)
                    }
                    DropdownMenu(open, { open = false }) {
                        types.forEach { option ->
                            DropdownMenuItem(text = { Text(option.name) }, onClick = { open = false; onContent(ScheduleEditing.assigning(option.id, index, content)) })
                        }
                    }
                }
            }
            repeat(7 - row.size) { Spacer(Modifier.weight(1f)) }
        }
    }
}

// Holidays

@Composable
private fun HolidayRow(region: String?, locale: Locale, onClick: () -> Unit) {
    val label = if (region.isNullOrEmpty()) stringResource(R.string.holidayCalendarOff) else regionName(region, locale)
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(onClick = onClick).padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.m),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(stringResource(R.string.holidayCalendar), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** The country's name in the app's language; Taiwan keeps the Traditional Chinese form for zh-Hant, as iOS does. */
fun regionName(code: String, locale: Locale): String {
    if (code == "TW" && locale.language == "zh" && (locale.script == "Hant" || locale.country in setOf("TW", "HK", "MO"))) return "台灣"
    return Locale("", code).getDisplayCountry(locale).ifEmpty { code }
}

private fun holidayName(day: HolidayCalendar.Day, locale: Locale): String {
    val tag = locale.toLanguageTag()
    return day.names[tag] ?: day.names[locale.language] ?: day.names["en"] ?: day.names.toSortedMap().values.firstOrNull().orEmpty()
}

@Composable
private fun HolidayRegionPicker(holidays: HolidayCalendar, locale: Locale, selection: String?, onDismiss: () -> Unit, onSelect: (String) -> Unit) {
    var query by remember { mutableStateOf("") }
    // Never switched on by itself; the device's region is only offered first.
    // The device's own region, not the app language's: the dataset is by country.
    val device = android.content.res.Resources.getSystem().configuration.locales[0].country.takeIf { it in holidays.regionIdentifiers }
    val featured = selection?.takeIf { it.isNotEmpty() } ?: device
    val regions = holidays.regionIdentifiers
        .filter { query.isEmpty() || regionName(it, locale).contains(query, ignoreCase = true) || it.contains(query, ignoreCase = true) }
        .filter { query.isNotEmpty() || it != featured }
        .sortedWith(compareBy(java.text.Collator.getInstance(locale)) { regionName(it, locale) })
    Dialog(onDismissRequest = onDismiss) {
        Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.surfaceContainerHigh, modifier = Modifier.heightIn(max = 560.dp)) {
            Column(Modifier.padding(vertical = DoneAtSpacing.l)) {
                Text(stringResource(R.string.holidayCalendar), Modifier.padding(horizontal = DoneAtSpacing.xl), style = MaterialTheme.typography.titleLarge)
                OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.m), placeholder = { Text(stringResource(R.string.holidayCalendarSearch)) }, singleLine = true)
                LazyColumn {
                    if (query.isEmpty()) {
                        item { RegionRow(stringResource(R.string.holidayCalendarOff), selection.isNullOrEmpty()) { onSelect("") } }
                        featured?.let { f ->
                            item {
                                val name = regionName(f, locale)
                                RegionRow(if (selection == f) name else Strings.holidayCalendarSystemDefault(LocalResources.current, name), selection == f) { onSelect(f) }
                            }
                        }
                    }
                    items(regions) { code -> RegionRow(regionName(code, locale), selection == code) { onSelect(code) } }
                }
                TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End).padding(end = DoneAtSpacing.l)) { Text(stringResource(R.string.cancelAction)) }
            }
        }
    }
}

@Composable
private fun RegionRow(title: String, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(onClick = onClick).padding(horizontal = DoneAtSpacing.xl), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        if (selected) Icon(Icons.Outlined.Check, null, tint = MaterialTheme.colorScheme.primary)
    }
}

// The selected day

@Composable
private fun SelectedDay(
    selected: String,
    today: String,
    locale: Locale,
    content: ExtendedScheduleContent,
    handSet: Map<String, java.util.UUID>,
    resolver: ExtendedScheduleResolver,
    holidays: HolidayCalendar,
    typeForDay: (String, java.util.UUID?) -> ShiftType?,
    canEdit: Boolean,
    hoursLabel: (ShiftType) -> String,
    onTypes: () -> Unit,
    onAssign: (java.util.UUID) -> Unit,
    onFollowPattern: () -> Unit,
) {
    val result = ExtendedScheduleResolver.dayNumber(selected)?.let { resolver.day(it) }
    val type = typeForDay(selected, result?.shiftTypeID)
    val region = content.holidayRegionIdentifier?.takeIf { it.isNotEmpty() }
    val holiday = region?.let { holidays.day(dateCode(selected), it) }
    Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.s)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).padding(start = DoneAtSpacing.xs)) {
                Text(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "MMMMdEEEE"), locale).format(LocalDate.parse(selected)), style = MaterialTheme.typography.titleSmall)
                holiday?.let {
                    Text("${holidayName(it, locale)} · ${stringResource(if (it.isWorkday) R.string.holidayMakeupWorkday else R.string.holidayRestDay)}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(
                    stringResource(
                        when (result?.source) {
                            ExtendedScheduleDay.Source.HAND_SET -> R.string.extendedSetByHand
                            ExtendedScheduleDay.Source.HOLIDAY -> R.string.holidaySource
                            ExtendedScheduleDay.Source.RULE -> R.string.extendedPattern
                            ExtendedScheduleDay.Source.CARRIED_OVER -> R.string.extendedCarriedOver
                            else -> R.string.extendedUnassigned
                        },
                    ),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(onClick = onTypes) { Icon(Icons.Outlined.MoreHoriz, stringResource(R.string.extendedShiftTypes), tint = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        if (!canEdit) Text(stringResource(R.string.extendedHistoryNeedsCareer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Column {
                ScheduleEditing.activeTypes(content).forEachIndexed { index, option ->
                    if (index > 0) com.rainif.doneat.ui.components.RowDivider()
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(enabled = canEdit) { onAssign(option.id) }
                            .semantics { this.selected = type?.id == option.id }
                            .padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.m),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.size(8.dp).background(typeColor(option), CircleShape))
                        Text(option.name, Modifier.weight(1f).padding(horizontal = DoneAtSpacing.m), style = MaterialTheme.typography.bodyMedium, color = if (canEdit) Color.Unspecified else MaterialTheme.colorScheme.onSurfaceVariant)
                        if (option.kind == ShiftType.Kind.WORK) Text(hoursLabel(option), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Icon(Icons.Outlined.Check, null, Modifier.padding(start = DoneAtSpacing.s).size(18.dp), tint = if (type?.id == option.id) MaterialTheme.colorScheme.primary else Color.Transparent)
                    }
                }
            }
        }
        if (handSet[selected] != null) {
            TextButton(onClick = onFollowPattern, enabled = canEdit) {
                Icon(Icons.AutoMirrored.Outlined.Undo, null, Modifier.size(18.dp))
                Text(stringResource(if (content.rule == null) R.string.extendedClearDay else R.string.extendedFollowPattern), Modifier.padding(start = DoneAtSpacing.s))
            }
        }
    }
}

/**
 * Ids for the preview a fixed schedule is shown as. Derived, not random, so
 * the calendar and the shift-type pages seed the same types independently.
 */
fun seedIds(): () -> java.util.UUID {
    var n = 0
    return { java.util.UUID.nameUUIDFromBytes("doneat.schedule.seed.${n++}".toByteArray()) }
}

/** A type's colour dot; an unreadable stored colour falls back to grey. */
fun typeColor(type: ShiftType): Color = runCatching { Color(type.colorHex.toColorInt()) }.getOrElse { Color.Gray }

/** "08:00–16:00", "20:00–06:00 next day", or "Rest". */
fun hoursLabel(res: android.content.res.Resources, type: ShiftType): String {
    if (type.kind != ShiftType.Kind.WORK) return res.getString(R.string.extendedKindRest)
    val start = ShiftSession.timeString(type.startMinutes)
    val end = ShiftSession.timeString(type.endMinutes)
    return if (type.endMinutes <= type.startMinutes) Strings.extendedHoursOvernight(res, start, end) else "$start–$end"
}
