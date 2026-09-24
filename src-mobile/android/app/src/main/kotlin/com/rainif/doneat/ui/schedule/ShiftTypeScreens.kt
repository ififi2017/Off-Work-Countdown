package com.rainif.doneat.ui.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ErrorOutline
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.core.graphics.toColorInt
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.schedule.ExtendedScheduleContent
import com.rainif.doneat.core.domain.schedule.ScheduleHours
import com.rainif.doneat.core.domain.schedule.ScheduleMode
import com.rainif.doneat.core.domain.schedule.ScheduleRuleInput
import com.rainif.doneat.core.domain.schedule.ScheduleRules
import com.rainif.doneat.core.domain.schedule.ShiftType
import com.rainif.doneat.core.domain.schedule.WorkSchedule
import com.rainif.doneat.core.domain.session.ScheduleEditing
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.core.domain.session.seededExtendedContent
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.components.SettingsFooter
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.components.SwitchRow
import com.rainif.doneat.ui.onboarding.appIsDark
import com.rainif.doneat.ui.onboarding.showTimePicker
import java.util.UUID

/** The draft's content, as the schedule page shows it (seeded from the fixed hours when there is none). */
@Composable
private fun draftContent(graph: AppGraph): ExtendedScheduleContent {
    val draft by graph.scheduleDraft.collectAsStateWithLifecycle()
    val session by graph.sessions.session.collectAsStateWithLifecycle()
    val workName = stringResource(R.string.extendedDefaultWorkShift)
    val restName = stringResource(R.string.extendedDefaultRest)
    val seed = remember(session.env.extendedSchedule == null) { session.seededExtendedContent(draft, System.currentTimeMillis().toDouble(), workName, restName, seedIds()) }
    return draft.extendedContent ?: session.env.extendedSchedule?.content?.takeIf { session.env.isExtendedScheduleEnabled } ?: seed
}

/** Puts [content] into the page's draft, as the calendar does. */
private fun AppGraph.updateDraftContent(content: ExtendedScheduleContent) {
    val session = sessions.session.value
    val manual = !(scheduleDraft.value.extendedScheduleEnabled ?: session.env.isExtendedScheduleEnabled) &&
        (scheduleDraft.value.scheduleMode ?: session.scheduleMode) == ScheduleMode.OFF
    scheduleDraft.value = scheduleDraft.value.copy(extendedContent = content, extendedScheduleEnabled = !manual)
        .settled(session.env, session.state, System.currentTimeMillis().toDouble())
}

/** The shift types the schedule offers (iOS `ExtendedShiftTypesSection`). */
@Composable
fun ShiftTypesScreen(graph: AppGraph, open: (Route) -> Unit, onBack: () -> Unit) {
    val content = draftContent(graph)
    val res = LocalResources.current
    DoneAtPage(stringResource(R.string.extendedShiftTypes), onBack, stringResource(R.string.workSchedule)) {
        SettingsGroup {
            ScheduleEditing.activeTypes(content).forEach { type ->
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable { open(Route.ShiftTypeEdit(type.id.toString(), isNew = false)) }.padding(horizontal = DoneAtSpacing.l),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(10.dp).background(typeColor(type), CircleShape))
                    Text(type.name, Modifier.weight(1f).padding(horizontal = DoneAtSpacing.m), style = MaterialTheme.typography.bodyLarge)
                    // A rest type called "Rest" does not need saying twice.
                    hoursLabel(res, type).takeIf { it != type.name }?.let {
                        Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                RowDivider()
            }
            Row(
                Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable { open(Route.ShiftTypeEdit(UUID.randomUUID().toString(), isNew = true)) }.padding(horizontal = DoneAtSpacing.l),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Outlined.Add, null, tint = MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.extendedAddShiftType), Modifier.padding(start = DoneAtSpacing.m), color = MaterialTheme.colorScheme.primary)
            }
        }
    }
}

/**
 * One shift type (iOS `ShiftTypeEditorSheet`). Save writes it into the page's
 * draft only; nothing is stored until the schedule page saves. A type the
 * pattern still hands out cannot be deleted; a saved one is archived.
 */
@Composable
fun ShiftTypeEditScreen(graph: AppGraph, id: String, isNew: Boolean, onBack: () -> Unit) {
    val content = draftContent(graph)
    val session by graph.sessions.session.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val dark = appIsDark()
    val uuid = UUID.fromString(id)
    val prefs = session.env.preferences
    val initial = remember(id) {
        content.shiftTypes.firstOrNull { it.id == uuid } ?: ShiftType(
            uuid, "", ShiftType.Kind.WORK, prefs.startMinutes, prefs.endMinutes, false, 12 * 60, 30, ScheduleEditing.nextColor(content.shiftTypes), false,
        )
    }
    var draft by remember(id) { mutableStateOf(initial) }
    val trimmed = draft.copy(name = draft.name.trim())
    val breakFits = breakFits(draft, session)
    val handSet = session.env.handSetDays
    val inUse = ScheduleEditing.ruleUses(uuid, content) ||
        (session.env.extendedSchedule?.content?.shiftTypes?.none { it.id == uuid } != false && uuid in handSet.values)

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.safeDrawingPadding()) {
            Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = DoneAtSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) { Icon(Icons.Outlined.Close, stringResource(R.string.cancelAction)) }
                Text(stringResource(if (isNew) R.string.extendedNewShiftType else R.string.extendedEditShiftType), Modifier.weight(1f), style = MaterialTheme.typography.titleLarge)
                TextButton(onClick = {
                    graph.updateDraftContent(ScheduleEditing.upserting(trimmed, content))
                    onBack()
                }, enabled = trimmed.isValid && breakFits) { Text(stringResource(R.string.saveAction), fontWeight = FontWeight.SemiBold) }
            }
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).wrapContentWidth(Alignment.CenterHorizontally).widthIn(max = 600.dp),
                verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l),
            ) {
                Column(Modifier.padding(horizontal = DoneAtSpacing.page), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
                    OutlinedTextField(
                        draft.name, { draft = draft.copy(name = it.take(ShiftType.MAXIMUM_NAME_LENGTH)) }, Modifier.fillMaxWidth(),
                        placeholder = { Text(stringResource(R.string.extendedShiftNamePlaceholder)) }, singleLine = true,
                    )
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        listOf(ShiftType.Kind.WORK to R.string.extendedKindWork, ShiftType.Kind.REST to R.string.extendedKindRest).forEachIndexed { i, (kind, label) ->
                            SegmentedButton(draft.kind == kind, { draft = draft.copy(kind = kind) }, SegmentedButtonDefaults.itemShape(i, 2)) { Text(stringResource(label)) }
                        }
                    }
                    if (draft.kind == ShiftType.Kind.REST) SettingsFooter(stringResource(R.string.extendedRestKindNote))
                }
                if (draft.kind == ShiftType.Kind.WORK) {
                    SettingsGroup(footer = if (draft.endMinutes <= draft.startMinutes) stringResource(R.string.extendedOvernightNote) else null) {
                        TimeRow(stringResource(R.string.startTime), draft.startMinutes) { showTimePicker(context, dark, draft.startMinutes) { m -> draft = draft.copy(startMinutes = m) } }
                        RowDivider()
                        TimeRow(stringResource(R.string.endTime), draft.endMinutes) { showTimePicker(context, dark, draft.endMinutes) { m -> draft = draft.copy(endMinutes = m) } }
                    }
                    SettingsGroup {
                        SwitchRow(stringResource(R.string.extendedBreak), draft.breakEnabled, { on ->
                            draft = draft.copy(breakEnabled = on, breakDurationMinutes = if (on && draft.breakDurationMinutes < 5) 30 else draft.breakDurationMinutes)
                        })
                        if (draft.breakEnabled) {
                            RowDivider()
                            TimeRow(stringResource(R.string.extendedBreakStart), draft.breakStartMinutes) { showTimePicker(context, dark, draft.breakStartMinutes) { m -> draft = draft.copy(breakStartMinutes = m) } }
                            RowDivider()
                            Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(start = DoneAtSpacing.l, end = DoneAtSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
                                Text(stringResource(R.string.extendedBreakDuration), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                                TextButton(onClick = { draft = draft.copy(breakDurationMinutes = (draft.breakDurationMinutes - 5).coerceAtLeast(5)) }, enabled = draft.breakDurationMinutes > 5) { Text("−") }
                                Text(Strings.minutesShort(LocalResources.current, draft.breakDurationMinutes.toString()), style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"))
                                TextButton(onClick = { draft = draft.copy(breakDurationMinutes = (draft.breakDurationMinutes + 5).coerceAtMost(240)) }, enabled = draft.breakDurationMinutes < 240) { Text("+") }
                            }
                        }
                    }
                    if (!breakFits) {
                        Row(Modifier.padding(horizontal = DoneAtSpacing.xl), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Outlined.ErrorOutline, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.error)
                            Text(stringResource(R.string.extendedBreakOutside), Modifier.padding(start = DoneAtSpacing.s), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
                SettingsGroup(title = stringResource(R.string.extendedColor)) {
                    Row(Modifier.fillMaxWidth().padding(DoneAtSpacing.l), horizontalArrangement = Arrangement.SpaceBetween) {
                        (ScheduleEditing.PALETTE + ScheduleEditing.REST_COLOR).distinct().forEach { hex ->
                            val chosen = draft.colorHex.equals(hex, ignoreCase = true)
                            Box(
                                Modifier.size(28.dp).background(Color(hex.toColorInt()), CircleShape)
                                    .then(if (chosen) Modifier.border(3.dp, MaterialTheme.colorScheme.onSurface, CircleShape) else Modifier)
                                    .clickable { draft = draft.copy(colorHex = hex) }
                                    .semantics { contentDescription = hex; selected = chosen },
                            )
                        }
                    }
                }
                if (!isNew) {
                    SettingsGroup(footer = if (inUse) stringResource(R.string.extendedShiftTypeInUse) else null) {
                        TextButton(
                            onClick = {
                                graph.updateDraftContent(ScheduleEditing.removing(uuid, content, session.env.extendedSchedule?.content))
                                onBack()
                            },
                            enabled = !inUse, modifier = Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.s),
                        ) { Text(stringResource(R.string.extendedDeleteShiftType), color = if (inUse) Color.Unspecified else MaterialTheme.colorScheme.error) }
                    }
                }
            }
        }
    }
}

@Composable
private fun TimeRow(title: String, minutes: Int, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(onClick = onClick).padding(horizontal = DoneAtSpacing.l), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Text(ShiftSession.timeString(minutes), style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"), color = MaterialTheme.colorScheme.primary)
    }
}

/** Whether a type's break falls inside its shift, asked of the same rule that checks the fixed lunch. */
private fun breakFits(type: ShiftType, session: ShiftSession): Boolean {
    if (type.kind != ShiftType.Kind.WORK || !type.breakEnabled || type.breakDurationMinutes <= 0) return true
    return ScheduleRules.validateBreak(
        ScheduleRuleInput(
            ScheduleHours(
                ShiftSession.timeString(type.startMinutes), ShiftSession.timeString(type.endMinutes), listOf(0, 1, 2, 3, 4, 5, 6),
                WorkSchedule(ScheduleMode.CLASSIC), ShiftSession.timeString(type.breakStartMinutes), type.breakDurationMinutes,
            ),
            System.currentTimeMillis().toDouble(), session.countdownZone,
        ),
    )
}
