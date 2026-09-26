package com.rainif.doneat.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.data.RecordsConflictResolution
import com.rainif.doneat.core.domain.records.ImportConflictCopy
import com.rainif.doneat.core.domain.records.RecordEntityType
import com.rainif.doneat.core.domain.records.ScheduleHoursCodec
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.ui.components.DoneAtPage
import com.rainif.doneat.ui.components.SettingsGroup
import com.rainif.doneat.ui.timer.EarningsGate
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import java.util.Base64
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** File-import conflicts are local to this archive; the first release has no account sync. */
@Composable
fun RecordsConflictCenter(graph: AppGraph, onBack: () -> Unit) {
    val records by graph.records.state.collectAsStateWithLifecycle()
    val device by graph.settings.device.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val ownerReason = stringResource(R.string.recordsOwnerAuthReason)
    val ownerAuthenticationFailed = stringResource(R.string.recordsOperationOwnerAuthenticationFailed)
    val scope = rememberCoroutineScope()
    var unlocked by remember(device.hideEarnings) { mutableStateOf(!device.hideEarnings) }
    var authDenied by remember(device.hideEarnings) { mutableStateOf(false) }
    var authAttempt by remember(device.hideEarnings) { mutableStateOf(0) }
    var failed by remember { mutableStateOf<Triple<ImportConflictCopy, Any, RecordsConflictResolution.Choice>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    LaunchedEffect(device.hideEarnings, authAttempt) {
        if (device.hideEarnings && !unlocked) {
            if (EarningsGate.confirmOwner(context, ownerReason) == EarningsGate.Result.REFUSED) authDenied = true
            else unlocked = true
        }
    }
    if (device.hideEarnings && !unlocked) {
        DoneAtPage(stringResource(R.string.recordsConflictCenter), onBack, stringResource(R.string.recordsDataTitle)) {
            if (authDenied) {
                Text(ownerAuthenticationFailed, Modifier.padding(horizontal = DoneAtSpacing.page))
                TextButton(onClick = { authDenied = false; authAttempt++ }) { Text(stringResource(R.string.retryAction)) }
            }
        }
        return
    }
    fun choose(conflict: ImportConflictCopy, review: RecordsConflictResolution.Review, choice: RecordsConflictResolution.Choice) {
        if (busy) return
        busy = true
        scope.launch {
            if (graph.settings.device.value.hideEarnings && EarningsGate.confirmOwner(context, ownerReason) == EarningsGate.Result.REFUSED) {
                error = ownerAuthenticationFailed
                busy = false
                return@launch
            }
            if (RecordsConflictResolution.resolve(graph.records, conflict, review.current, choice, graph.nowMs(), graph.newId)) {
                failed = null
            } else {
                failed = Triple(conflict, review.current, choice)
            }
            busy = false
        }
    }

    DoneAtPage(stringResource(R.string.recordsConflictCenter), onBack, stringResource(R.string.recordsDataTitle)) {
        if (records.importConflicts.isEmpty()) {
            Text(stringResource(R.string.recordsConflictNone), Modifier.padding(horizontal = DoneAtSpacing.page))
        }
        records.importConflicts.forEach { conflict ->
            val review = RecordsConflictResolution.review(records, conflict)
            SettingsGroup(title = conflictTitle(conflict.entityType, review?.title)) {
                Column(verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.xs), modifier = Modifier.fillMaxWidth()
                    .padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.m)) {
                    if (review == null || review.fields.isEmpty()) Text(stringResource(R.string.recordsConflictDetailsUnreadable))
                    review?.fields?.forEach { field ->
                        Text(fieldLabel(field.name, conflict.entityType), style = MaterialTheme.typography.labelMedium)
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(DoneAtSpacing.m)) {
                            Column(Modifier.weight(1f)) {
                                Text(stringResource(R.string.recordsConflictCurrentVersion), style = MaterialTheme.typography.labelSmall)
                                Text(conflictValue(field.current, field.name, graph), style = MaterialTheme.typography.bodySmall)
                            }
                            Column(Modifier.weight(1f)) {
                                Text(stringResource(R.string.recordsConflictOtherVersion), style = MaterialTheme.typography.labelSmall)
                                Text(conflictValue(field.incoming, field.name, graph), style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                    if (review?.canUseIncoming == false) Text(stringResource(R.string.recordsConflictIncomingZoneBlocked), style = MaterialTheme.typography.bodySmall)
                    TextButton(enabled = !busy && review != null, onClick = { review?.let { choose(conflict, it, RecordsConflictResolution.Choice.KEEP_CURRENT) } }) {
                        Text(stringResource(R.string.recordsConflictKeepLocal))
                    }
                    TextButton(enabled = !busy && review?.canUseIncoming == true, onClick = { review?.let { choose(conflict, it, RecordsConflictResolution.Choice.USE_IMPORTED) } }) {
                        Text(stringResource(R.string.recordsConflictKeepIncoming))
                    }
                }
            }
        }
    }
    failed?.let { (conflict, expected, choice) ->
        AlertDialog(
            onDismissRequest = { failed = null },
            title = { Text(stringResource(R.string.recordsArchiveSaveFailedTitle)) },
            text = { Text(stringResource(R.string.recordsArchiveSaveFailedBody)) },
            confirmButton = { TextButton(onClick = {
                failed = null
                RecordsConflictResolution.review(records, conflict)?.takeIf { it.current == expected }?.let { choose(conflict, it, choice) }
            }) { Text(stringResource(R.string.retryAction)) } },
            dismissButton = { TextButton(onClick = { failed = null }) { Text(stringResource(R.string.close)) } },
        )
    }
    error?.let { message ->
        AlertDialog(onDismissRequest = { error = null }, title = { Text(stringResource(R.string.recordsDataTitle)) },
            text = { Text(message) }, confirmButton = { TextButton(onClick = { error = null }) { Text(stringResource(R.string.close)) } })
    }
}

@Composable
private fun conflictTitle(type: RecordEntityType, detail: String?): String {
    val label = when (type) {
        RecordEntityType.CAREER_PERIOD, RecordEntityType.SCHEDULE_SNAPSHOT, RecordEntityType.EXTENDED_SCHEDULE,
        RecordEntityType.ROSTER_DAY -> stringResource(R.string.workSchedule)
        RecordEntityType.CALENDAR_EXCEPTION, RecordEntityType.DAY_OVERRIDE, RecordEntityType.WORK_OBSERVATION -> stringResource(R.string.recordsTitle)
        RecordEntityType.LIFE_PROFILE -> stringResource(R.string.recordsLifeProfileRow)
        RecordEntityType.FOCUS_TASK -> stringResource(R.string.focusTaskTitle)
        RecordEntityType.FOCUS_SESSION -> stringResource(R.string.focusHistory)
        RecordEntityType.FOCUS_PLANNING_CONFIGURATION -> stringResource(R.string.focusPlanTitle)
        RecordEntityType.SYNCED_PREFERENCES -> stringResource(R.string.settings)
    }
    val shown = detail?.let { raw -> runCatching { DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(LocalDate.parse(raw)) }.getOrDefault(raw) }
    return if (shown.isNullOrBlank()) label else "$label · $shown"
}

@Composable
private fun fieldLabel(name: String, type: RecordEntityType): String = when (name) {
    "note", "label" -> stringResource(R.string.recordsConflictFieldNote)
    "kind", "effect", "isCleared" -> stringResource(R.string.recordsSectionKind)
    "segments" -> stringResource(R.string.recordsSectionHours)
    "startsOn", "startedAtMs", "occurredAtMs" -> stringResource(R.string.startTime)
    "endsBefore", "plannedEndAtMs", "endedAtMs" -> stringResource(R.string.endTime)
    "effectiveFrom", "configurationData" -> stringResource(R.string.workSchedule)
    "recordsTimeZoneIdentifier" -> stringResource(R.string.recordsTimeZone)
    "shiftAnchorDate", "plannedForDate", "scheduledStartAtMs", "shiftTypeID" -> stringResource(R.string.focusSchedule)
    "birthYear", "bornOn" -> stringResource(R.string.lifeBirthYear)
    "schoolStartedOn" -> stringResource(R.string.lifeSchoolStarted)
    "workStartedOn", "workStartedPartial" -> stringResource(R.string.lifeWorkStarted)
    "retirementOn" -> stringResource(R.string.lifeRetirementDate)
    "retirementAge" -> stringResource(R.string.lifeRetirementAge)
    "averageSleepHours", "averageSleepMinutes" -> stringResource(R.string.lifeSleepHours)
    "hidesExactAges" -> stringResource(R.string.lifeHideAges)
    "sleepSource" -> stringResource(R.string.recordsSleep)
    "workHistoryMode" -> stringResource(R.string.lifeWorkHistoryMode)
    "roughCurrentSalary" -> stringResource(R.string.lifeCurrentSalary)
    "employmentPeriods" -> stringResource(R.string.lifeIncomeHistory)
    "title" -> stringResource(R.string.focusTaskTitle)
    "estimatedPomodoros" -> stringResource(R.string.focusPomodoros)
    "icon" -> stringResource(R.string.focusChooseIcon)
    "isFavorite" -> stringResource(R.string.focusFavorites)
    "completedAtMs", "deletedAtMs", "endReason", "plannedEndReason" -> stringResource(R.string.plusStatus)
    else -> stringResource(if (type == RecordEntityType.FOCUS_TASK) R.string.focusTaskTitle else R.string.recordsSectionKind)
}

@Composable
private fun conflictValue(value: JsonElement?, field: String, graph: AppGraph): String {
    if (value == null || value is JsonNull) return "—"
    if (field == "configurationData" && value is JsonPrimitive) {
        return ScheduleHoursCodec.decodeBase64(value.content)?.let { "${it.startTime}–${it.endTime}" } ?: "—"
    }
    if (field == "valueData" && value is JsonPrimitive) {
        val decoded = runCatching { String(Base64.getDecoder().decode(value.content)) }.getOrNull()
        val end = decoded?.let { Regex("\"overtimeEndAtMs\"\\s*:\\s*([0-9.]+)").find(it)?.groupValues?.get(1)?.toDoubleOrNull() }
        return end?.let { conflictDate(it, graph) } ?: stringResource(R.string.recordsSectionKind)
    }
    if (value is JsonPrimitive) {
        val content = value.content
        if (field == "shiftTypeID") return graph.records.state.value.extendedSchedule?.content?.shiftTypes
            ?.firstOrNull { it.id.toString() == content }?.name ?: stringResource(R.string.workSchedule)
        if (field.endsWith("AtMs")) {
            return content.toDoubleOrNull()?.let { conflictDate(it, graph) } ?: "—"
        }
        return when (content) {
            "true" -> "✓"; "false" -> "—"
            "confirmedAsScheduled" -> stringResource(R.string.recordsConfirmScheduled)
            "customSegments" -> stringResource(R.string.recordsKindCustomHours)
            "notWorking" -> stringResource(R.string.recordsMarkLeave)
            "cleared" -> stringResource(R.string.recordsClearDay)
            "timerSurfaceFirstSeen" -> stringResource(R.string.recordsObservedFirstSeen)
            "countdownStarted" -> stringResource(R.string.recordsObservedStarted)
            "countdownStopped" -> stringResource(R.string.recordsObservedStopped)
            "overtimeDeclared" -> stringResource(R.string.recordsObservedOvertime)
            "stoppedByUser" -> stringResource(R.string.focusHistoryStopped)
            "stoppedAtBoundary" -> stringResource(R.string.focusHistoryBoundary)
            "abandoned" -> stringResource(R.string.focusHistoryAbandoned)
            "supersededBySync" -> stringResource(R.string.focusHistorySupersededBySync)
            "rough" -> stringResource(R.string.lifeWorkHistoryRough)
            "detailed" -> stringResource(R.string.lifeWorkHistoryDetailed)
            "monthly" -> stringResource(R.string.lifeSalaryMonthly)
            "yearly" -> stringResource(R.string.lifeSalaryYearly)
            "healthSuggested" -> stringResource(R.string.recordsSleepFromHealth)
            else -> if (content.matches(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}"))) stringResource(R.string.recordsConflictItems) else content
        }
    }
    if (value is JsonArray && field == "segments") return value.mapNotNull { segment ->
        val row = segment as? JsonObject ?: return@mapNotNull null
        val start = row["startAtMs"]?.jsonPrimitive?.content?.toDoubleOrNull()?.let { conflictDate(it, graph) }
        val end = row["endAtMs"]?.jsonPrimitive?.content?.toDoubleOrNull()?.let { conflictDate(it, graph) }
        if (start != null && end != null) "$start–$end" else null
    }.joinToString(", ").ifEmpty { "—" }
    if (value is JsonArray) {
        if (value.isEmpty()) return "—"
        val parts = mutableListOf<String>()
        for (part in value.take(3)) parts += conflictValue(part, "", graph)
        val examples = parts.joinToString("; ")
        return if (value.size > 3) "$examples · ${value.size} ${stringResource(R.string.recordsConflictItems)}" else examples
    }
    if (value is JsonObject) {
        val year = value["year"]?.jsonPrimitive?.content
        if (year != null) return listOfNotNull(year, value["month"]?.jsonPrimitive?.content, value["day"]?.jsonPrimitive?.content).joinToString("-")
        val parts = mutableListOf<String>()
        for ((key, part) in value) {
            if (key == "id" || key.endsWith("ID")) continue
            val shown = conflictValue(part, key, graph)
            if (shown != "—") parts += shown
            if (parts.size == 4) break
        }
        return parts.joinToString(" · ").ifEmpty { "—" }
    }
    return "—"
}

private fun conflictDate(ms: Double, graph: AppGraph): String = runCatching {
    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT)
        .withZone(ZoneId.of(graph.settings.preferences.value.recordsTimeZoneIdentifier))
        .format(Instant.ofEpochMilli(ms.toLong()))
}.getOrDefault("—")
