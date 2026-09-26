package com.rainif.doneat.ui.records

import android.view.HapticFeedbackConstants
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Redo
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.FlightTakeoff
import androidx.compose.material.icons.outlined.Hotel
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.material.icons.outlined.WbTwilight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.data.RecordsEditing
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.records.DayEditDraft
import com.rainif.doneat.core.domain.records.DayRecordWrite
import com.rainif.doneat.core.domain.records.RecordEditContext
import com.rainif.doneat.ui.components.ChoiceRow
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.PageFooter
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.onboarding.rememberTimePicker
import com.rainif.doneat.ui.timer.Haptics
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.LocalTime

/** Which draft kinds offer themselves, in iOS's order, with their words and marks. */
private val KINDS = listOf(
    Triple(DayEditDraft.Kind.CUSTOM_HOURS, R.string.recordsKindCustomHours, Icons.Outlined.Schedule),
    Triple(DayEditDraft.Kind.AS_SCHEDULED, R.string.recordsConfirmScheduled, Icons.Outlined.CalendarMonth),
    Triple(DayEditDraft.Kind.LEAVE, R.string.recordsMarkLeave, Icons.Outlined.FlightTakeoff),
    Triple(DayEditDraft.Kind.REST_DAY, R.string.recordsMarkRest, Icons.Outlined.Hotel),
    Triple(DayEditDraft.Kind.MAKEUP_DAY, R.string.recordsMarkMakeup, Icons.AutoMirrored.Outlined.Redo),
)

/** Opens a day's editor with a draft loaded from the archive as it stands. */
fun beginDayEdit(graph: AppGraph, context: RecordsContext, dayKey: String, open: (com.rainif.doneat.ui.Route) -> Unit) {
    val day = LocalDate.parse(dayKey)
    val resolution = context.queries.resolvedDays(day, day).firstOrNull()
    graph.dayEditDraft.value = DayEditDraft.load(dayKey, context.queries.state, resolution, context.queries.zone.id)
    open(com.rainif.doneat.ui.Route.RecordsDayEdit(dayKey))
}

/**
 * Editing one day's record (iOS `RecordDayEditView`): pick what the day was,
 * adjust its hours, then one Save. Nothing is written before Save, and
 * leaving with changes asks first.
 */
@Composable
fun RecordsDayEditScreen(graph: AppGraph, dayKey: String, onBack: () -> Unit) {
    val context = rememberRecordsContext(graph)
    val text = context.text
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val pickTime = rememberTimePicker()
    val stored by graph.dayEditDraft.collectAsStateWithLifecycle()
    LaunchedEffect(dayKey) {
        if (graph.dayEditDraft.value?.dayKey != dayKey) {
            val day = LocalDate.parse(dayKey)
            graph.dayEditDraft.value = DayEditDraft.load(dayKey, context.queries.state, context.queries.resolvedDays(day, day).firstOrNull(), context.queries.zone.id)
        }
    }
    val draft = stored?.takeIf { it.dayKey == dayKey } ?: return
    fun update(next: DayEditDraft) { graph.dayEditDraft.value = next }
    fun leave() {
        onBack()
    }
    var confirmsDiscard by remember { mutableStateOf(false) }
    var confirmsClear by remember { mutableStateOf(false) }
    var pendingKind by remember { mutableStateOf<DayEditDraft.Kind?>(null) }
    fun back() {
        if (draft.hasChanges) confirmsDiscard = true else leave()
    }
    BackHandler(enabled = draft.hasChanges) { confirmsDiscard = true }

    /** Writes [write] for the draft's day; the page closes only if [submission] still describes the draft on screen. */
    fun save(submission: DayEditDraft.Submission, write: DayRecordWrite = submission.write) {
        scope.launch {
            val now = graph.nowMs()
            val session = graph.sessions.session.value
            val editContext = RecordEditContext(
                nowMs = now,
                recordsTimeZone = graph.settings.preferences.value.recordsTimeZoneIdentifier,
                canEdit = graph.plus.authorized.value,
                holidays = graph.holidays.value,
                currentHours = { session.hoursConfiguration(now) },
                newId = graph.newId,
            )
            val saved = RecordsEditing.save(graph.records, submission.copy(write = write), editContext)
            // A result that no longer matches the draft on screen belongs to an edit the user has moved past.
            if (saved && graph.dayEditDraft.value?.stillMatches(submission) == true) {
                Haptics.confirm(view)
                leave()
            }
        }
    }
    fun select(kind: DayEditDraft.Kind) {
        if (kind == draft.kind) return
        // Switching away from recorded hours throws them away, so it asks first.
        if (kind != DayEditDraft.Kind.CUSTOM_HOURS && draft.kind == DayEditDraft.Kind.CUSTOM_HOURS && draft.hasStoredOverride) {
            Haptics.warn(view)
            pendingKind = kind
            return
        }
        update(draft.withKind(kind))
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    }

    DoneAtPage(text.string(R.string.recordsEditDay), { back() }, text.dayTitle(dayKey)) {
        PageFooter(text.dayTitle(dayKey))
        if (draft.kind == DayEditDraft.Kind.CUSTOM_HOURS) {
            SettingsGroup(title = text.string(R.string.recordsSectionHours)) {
                TimeRow(Icons.Outlined.WbSunny, text.string(R.string.startTime), draft.startMinutes, text) {
                    pickTime(draft.startMinutes) { update(graph.dayEditDraft.value?.withStart(it) ?: draft) }
                }
                RowDivider()
                TimeRow(Icons.Outlined.WbTwilight, text.string(R.string.endTime), draft.endMinutes, text) {
                    pickTime(draft.endMinutes) { update(graph.dayEditDraft.value?.withEnd(it) ?: draft) }
                }
            }
        }
        SettingsGroup(title = text.string(R.string.recordsSectionKind)) {
            KINDS.forEachIndexed { index, (kind, title, icon) ->
                if (index > 0) RowDivider()
                ChoiceRow(text.string(title), draft.kind == kind, { select(kind) }, icon)
            }
        }
        Button(
            onClick = { save(draft.submission) },
            enabled = draft.hasChanges,
            modifier = Modifier.fillMaxWidth().padding(horizontal = DoneAtSpacing.page).heightIn(min = 52.dp),
        ) { Text(text.string(R.string.saveAction)) }
        if (draft.loadedKind != DayEditDraft.Kind.CUSTOM_HOURS || draft.hasStoredOverride) {
            SettingsGroup {
                ListItem(
                    headlineContent = { Text(text.string(R.string.recordsClearDay), color = MaterialTheme.colorScheme.error) },
                    supportingContent = { Text(text.string(R.string.recordsClearDayDetail)) },
                    leadingContent = { Icon(Icons.AutoMirrored.Outlined.Undo, null, tint = MaterialTheme.colorScheme.error) },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    modifier = Modifier.clickable(role = Role.Button) {
                        Haptics.warn(view)
                        confirmsClear = true
                    },
                )
            }
        }
    }

    if (confirmsDiscard) {
        AlertDialog(
            onDismissRequest = { confirmsDiscard = false },
            title = { Text(text.string(R.string.recordsDiscardEdits)) },
            confirmButton = {
                TextButton(onClick = { confirmsDiscard = false; leave() }) {
                    Text(text.string(R.string.recordsDiscardEdits), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmsDiscard = false }) { Text(text.string(R.string.cancelAction)) } },
        )
    }
    pendingKind?.let { kind ->
        AlertDialog(
            onDismissRequest = { pendingKind = null },
            title = { Text(text.string(R.string.recordsReplaceHoursTitle)) },
            text = { Text(text.string(R.string.recordsReplaceHoursConfirm)) },
            confirmButton = {
                TextButton(onClick = {
                    pendingKind = null
                    update(draft.withKind(kind))
                }) { Text(text.string(KINDS.first { it.first == kind }.second)) }
            },
            dismissButton = { TextButton(onClick = { pendingKind = null }) { Text(text.string(R.string.cancelAction)) } },
        )
    }
    if (confirmsClear) {
        AlertDialog(
            onDismissRequest = { confirmsClear = false },
            title = { Text(text.string(R.string.recordsClearDayTitle)) },
            text = { Text(text.string(R.string.recordsClearDayConfirm)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmsClear = false
                    save(draft.submission, DayRecordWrite.CLEAR)
                }) { Text(text.string(R.string.recordsClearDay), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmsClear = false }) { Text(text.string(R.string.cancelAction)) } },
        )
    }
}

@Composable
private fun TimeRow(icon: ImageVector, title: String, minutes: Int, text: RecordsText, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.Button, onClick = onClick).padding(horizontal = DoneAtSpacing.l),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, Modifier.weight(1f).padding(horizontal = DoneAtSpacing.l), style = MaterialTheme.typography.bodyLarge)
        Text(text.clock(LocalTime.of(minutes / 60, minutes % 60)), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary)
    }
}
