package com.rainif.doneat.ui.timer

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.session.OvertimeRestChoices
import com.rainif.doneat.core.domain.session.OvertimeSheetPlan
import com.rainif.doneat.core.domain.session.ShiftSession
import com.rainif.doneat.l10n.Strings
import com.rainif.doneat.ui.components.RowDivider
import com.rainif.doneat.ui.onboarding.rememberTimePicker
import java.time.Instant
import java.time.ZoneId

/**
 * Sets or moves the overtime (iOS `OvertimeSheet`, plan 024): until a clock
 * time or for how long, an optional rest before it, and how it is paid. The end
 * can be no earlier than the overtime's start or now, and has no minimum
 * length: after a clock-off it records time already worked.
 */
@Composable
fun OvertimeDialog(
    session: ShiftSession,
    text: TimerText,
    dark: Boolean,
    onDismiss: () -> Unit,
    onConfirm: (endAtMs: Double, payMultiplier: Double, startAtMs: Double?) -> Unit,
) {
    val res = LocalResources.current
    val pickTime = rememberTimePicker()
    val zone = ZoneId.systemDefault()
    fun nowMs() = System.currentTimeMillis().toDouble()
    // Fixed on open, like iOS `OvertimeSheetMode`: the entry button already
    // says "Adjust overtime" once overtime is set.
    val mode = remember {
        val now = nowMs()
        OvertimeDialogs.mode(session.state.overtimeEndAtMs != null, session.snapshot(now)?.plannedEndAtMs, now)
    }
    var plan by remember { mutableStateOf(OvertimeDialogs.initialPlan(session, nowMs())) }
    var pay by remember {
        mutableStateOf(OvertimePayDraft.of(session.effectiveOvertimePayMultiplier, session.env.preferences.overtimePayMultiplier))
    }
    fun update(change: (OvertimeSheetPlan) -> OvertimeSheetPlan) {
        plan = change(plan.copy(nowMs = nowMs())).settled()
    }
    fun restLabel(minutes: Int) = if (minutes == 0) res.getString(R.string.overtimeRestNone) else text.relativeDuration(minutes * 60_000.0)
    val footnote = when {
        !pay.isPaid -> res.getString(R.string.overtimeUnpaidSheetNote)
        pay.multiplier == 1.0 -> res.getString(R.string.overtimeNoMultiplier)
        else -> Strings.overtimeMultiplierNote(res, decimal(pay.multiplier, text.locale))
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(mode.title)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(DoneAtSpacing.l)) {
                Text(stringResource(R.string.overtimeDescription), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    listOf(OvertimeSheetPlan.Entry.UNTIL to R.string.overtimeModeEnd, OvertimeSheetPlan.Entry.DURATION to R.string.overtimeModeDuration)
                        .forEachIndexed { index, (entry, label) ->
                            SegmentedButton(
                                selected = plan.entry == entry,
                                onClick = { update { it.selecting(entry) } },
                                shape = SegmentedButtonDefaults.itemShape(index, 2),
                            ) { Text(stringResource(label), maxLines = 1) }
                        }
                }
                Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxWidth()) {
                    Column {
                        when (plan.entry) {
                            OvertimeSheetPlan.Entry.UNTIL -> Row(
                                Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = DoneAtSpacing.l, vertical = DoneAtSpacing.s),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(stringResource(R.string.overtimeEndTime), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                                FilledTonalButton(onClick = {
                                    pickTime(ShiftSession.minutes(plan.untilMs, zone)) { minutes ->
                                        update { it.copy(untilMs = OvertimeDialogs.nextOccurrence(minutes, it.minimumEndMs, zone)) }
                                    }
                                }, shape = MaterialTheme.shapes.medium) {
                                    Text(text.eventTime(plan.untilMs, plan.nowMs), style = MaterialTheme.typography.titleMedium.copy(fontFeatureSettings = "tnum"))
                                }
                            }
                            OvertimeSheetPlan.Entry.DURATION -> {
                                val choices = plan.durationChoices
                                MenuRow(
                                    title = stringResource(R.string.overtimeDurationLabel),
                                    value = text.relativeDuration(plan.durationMinutes * 60_000.0),
                                    options = choices.map { text.relativeDuration(it * 60_000.0) },
                                    selected = choices.indexOf(plan.durationMinutes),
                                ) { index -> update { it.copy(durationMinutes = choices[index]) } }
                            }
                        }
                        RowDivider(inset = false)
                        MenuRow(
                            title = stringResource(R.string.overtimeRestRow),
                            value = restLabel(plan.restMinutes),
                            options = OvertimeRestChoices.minutes.map(::restLabel),
                            selected = OvertimeRestChoices.minutes.indexOf(plan.restMinutes),
                        ) { index -> update { it.copy(restMinutes = OvertimeRestChoices.minutes[index]) } }
                    }
                }
                Text(
                    stringResource(R.string.overtimeRestFootnote),
                    Modifier.padding(horizontal = DoneAtSpacing.l).offset(y = (-DoneAtSpacing.s)),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (plan.countedMs > 0) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.Schedule, null, Modifier.size(18.dp))
                        Text(
                            Strings.overtimePeriodSummary(res, text.time(plan.startMs), text.time(plan.endMs), text.relativeDuration(plan.countedMs)),
                            Modifier.padding(start = DoneAtSpacing.s),
                            style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"),
                            fontWeight = FontWeight.Medium,
                        )
                    }
                }
                OvertimePayCard(pay, text.locale, { pay = it }, containerColor = MaterialTheme.colorScheme.surface)
                Row(verticalAlignment = Alignment.Top) {
                    Icon(Icons.Outlined.Info, null, Modifier.size(18.dp).padding(top = 2.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(footnote, Modifier.padding(start = DoneAtSpacing.s), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val final = plan.copy(nowMs = nowMs()).settled()
                    plan = final
                    if (final.isValid) onConfirm(final.endMs, pay.payMultiplier, final.overtimeStartMs)
                },
                enabled = plan.isValid,
            ) { Text(stringResource(mode.confirm)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.close)) } },
    )
}

/** What the dialog is doing; decides its title and confirm label. */
internal enum class OvertimeDialogMode(val title: Int, val confirm: Int) {
    /** No overtime yet and the shift is still running. */
    Add(R.string.overtimeTitle, R.string.confirmOvertime),
    /** Overtime is already set; this moves its end. */
    Adjust(R.string.adjustOvertime, R.string.saveAction),
    /** No overtime yet, planned clock-off passed: recording time already worked. */
    Log(R.string.logOvertimeTitle, R.string.saveAction),
}

internal object OvertimeDialogs {
    /**
     * The sheet's first state: the existing overtime, including a rest that
     * made it its own last segment, or now for a retrospective record (so
     * someone who stayed late can save the time already worked).
     */
    fun initialPlan(session: ShiftSession, nowMs: Double): OvertimeSheetPlan {
        val snapshot = session.snapshot(nowMs)
        val plannedEnd = snapshot?.plannedEndAtMs ?: nowMs
        val existing = session.state.overtimeEndAtMs
        var plan = OvertimeSheetPlan(plannedEndMs = plannedEnd, nowMs = nowMs, untilMs = nowMs)
        val last = snapshot?.segments?.lastOrNull()
        if (existing != null && last != null && snapshot.plannedEndAtMs < last.startAtMs) {
            plan = plan.copy(restMinutes = OvertimeRestChoices.nearest((last.startAtMs - snapshot.plannedEndAtMs) / 60_000))
        }
        return plan.copy(untilMs = maxOf(plan.minimumEndMs, existing ?: nowMs)).settled()
    }

    fun mode(hasOvertime: Boolean, plannedEndAtMs: Double?, nowMs: Double): OvertimeDialogMode = when {
        hasOvertime -> OvertimeDialogMode.Adjust
        plannedEndAtMs != null && nowMs >= plannedEndAtMs -> OvertimeDialogMode.Log
        else -> OvertimeDialogMode.Add
    }

    /**
     * The first moment at the picked clock reading that is not before
     * [minimumMs]: later today, or tomorrow once today's has passed, so an
     * evening shift's overtime can run past midnight. The picked minute of the
     * minimum itself means the minimum.
     */
    fun nextOccurrence(minutes: Int, minimumMs: Double, zone: ZoneId): Double {
        val floor = Instant.ofEpochMilli(minimumMs.toLong()).atZone(zone)
        var candidate = floor.toLocalDate().atTime(minutes / 60, minutes % 60).atZone(zone)
        val minuteOfMinimum = floor.withSecond(0).withNano(0)
        if (candidate.isBefore(minuteOfMinimum)) candidate = candidate.toLocalDate().plusDays(1).atTime(minutes / 60, minutes % 60).atZone(zone)
        return maxOf(candidate.toInstant().toEpochMilli().toDouble(), minimumMs)
    }
}
