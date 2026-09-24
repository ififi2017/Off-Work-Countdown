package com.rainif.doneat.ui.records

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.rainif.doneat.AppGraph
import com.rainif.doneat.R
import com.rainif.doneat.core.designsystem.DoneAtSpacing
import com.rainif.doneat.core.domain.records.RecordsDayCanvasModel
import com.rainif.doneat.core.domain.records.RecordsDayInterval
import com.rainif.doneat.core.domain.records.RecordsDaySource
import com.rainif.doneat.core.domain.records.TimeAllocationKind
import com.rainif.doneat.core.domain.records.WorkObservationKind
import com.rainif.doneat.ui.Route
import com.rainif.doneat.ui.components.DoneAtPage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.LocalTime

/**
 * One civil day, midnight to midnight (iOS `RecordsDayCanvasView`). The week
 * and month compare days; this page explains one. Its single conclusion is the
 * waking time that was yours; the rest is the account of where the day went.
 */
@Composable
fun RecordsDayScreen(graph: AppGraph, dayKey: String, onBack: () -> Unit, openSettings: (Route?) -> Unit) {
    val context = rememberRecordsContext(graph)
    val text = context.text
    val model by produceState<RecordsDayCanvasModel?>(null, context, dayKey) {
        value = withContext(Dispatchers.Default) { context.queries.dayCanvas(dayKey, context.nowMs) }
    }
    DoneAtPage(text.dayTitle(dayKey), onBack, text.string(R.string.recordsTitle)) {
        val current = model ?: return@DoneAtPage
        Column(Modifier.padding(horizontal = DoneAtSpacing.page), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            if (current.isLocked) {
                LockedPlaceholder(LockedKind.DAY, text) { openSettings(Route.Plus) }
                return@Column
            }
            SourceChip(text.sourceTitle(current.source))
            RecordsCard { DayBandCard(current, text) }
            Conclusion(current, text)
            Segments(current, text)
            Observations(context, dayKey)
            // History edits arrive with the day editor; until then the page says what it can.
            if (!context.queries.authorized) {
                Text(
                    text.string(R.string.recordsEditPlusHint),
                    Modifier.padding(horizontal = 4.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun SourceChip(title: String) {
    Surface(shape = RoundedCornerShape(9.dp), color = MaterialTheme.colorScheme.surfaceContainerHighest) {
        Text(
            title,
            Modifier.padding(horizontal = 9.dp, vertical = 5.dp),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun spoken(interval: RecordsDayInterval, text: RecordsText, sleepFromHealth: Boolean) = listOf(
    text.timeRange(interval.startAtMs, interval.endAtMs),
    text.kindTitle(interval.kind),
    text.duration(interval.durationMs.toDouble()),
    sourceWords(interval, text, sleepFromHealth),
).joinToString(", ")

private fun sourceWords(interval: RecordsDayInterval, text: RecordsText, sleepFromHealth: Boolean) =
    if (interval.unexplained) text.string(R.string.recordsSourceNone) else text.sourceTitle(interval.source, sleepFromHealth)

/**
 * The 24-hour strip (iOS `RecordsDayBand`). The model already cut the day out
 * of every shift, so this only paints; its order is the order a screen reader
 * hears, as words rather than pixels.
 */
@Composable
private fun DayBandCard(model: RecordsDayCanvasModel, text: RecordsText) {
    var selectedStart by rememberSaveable(model.dayKey) { mutableStateOf<Double?>(null) }
    val selected = model.intervals.firstOrNull { it.startAtMs == selectedStart }
        ?: model.intervals.firstOrNull { it.kind == TimeAllocationKind.WORK }
        ?: model.intervals.firstOrNull()
    val total = model.dayEndMs - model.dayStartMs
    val scheme = MaterialTheme.colorScheme
    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (selected != null) {
            Column(Modifier.clearAndSetSemantics {}) {
                Text("${text.kindTitle(selected.kind)} · ${text.timeRange(selected.startAtMs, selected.endAtMs)}", style = MaterialTheme.typography.labelLarge)
                Text(
                    listOf(
                        text.duration(selected.durationMs.toDouble()),
                        text.percent(if (model.allocation.dayLengthMs > 0) selected.durationMs * 100.0 / model.allocation.dayLengthMs else 0.0),
                        sourceWords(selected, text, model.sleepFromHealth),
                    ).joinToString(" · "),
                    style = MaterialTheme.typography.labelMedium,
                    color = scheme.onSurfaceVariant,
                )
            }
        }
        // A timeline reads left to right in every language.
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
            var width by androidx.compose.runtime.remember { mutableStateOf(IntSize.Zero) }
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(44.dp)
                    .onSizeChanged { width = it }
                    .pointerInput(model) {
                        detectTapGestures { offset ->
                            if (width.width <= 0 || total <= 0) return@detectTapGestures
                            val moment = model.dayStartMs + (offset.x / width.width).coerceIn(0f, 1f) * total
                            selectedStart = (model.intervals.firstOrNull { it.startAtMs <= moment && moment < it.endAtMs } ?: model.intervals.lastOrNull())?.startAtMs
                        }
                    }
                    .semantics {
                        contentDescription = text.string(R.string.recordsDaySegments)
                        customActions = model.intervals.map { interval ->
                            CustomAccessibilityAction(spoken(interval, text, model.sleepFromHealth)) { selectedStart = interval.startAtMs; true }
                        }
                    },
                contentAlignment = Alignment.CenterStart,
            ) {
                Row(Modifier.fillMaxWidth().height(26.dp).clip(RoundedCornerShape(10.dp)).background(scheme.surfaceContainerHighest)) {
                    model.intervals.forEach { interval ->
                        val fraction = if (total > 0) ((interval.endAtMs - interval.startAtMs) / total).toFloat() else 0f
                        if (fraction <= 0f) return@forEach
                        Box(
                            Modifier.weight(fraction).fillMaxHeight().background(kindColor(interval.kind))
                                .estimatedHatch(interval.source.isEstimated, androidx.compose.ui.graphics.Color.White, spacing = 4.dp)
                                .border(2.dp, if (interval == selected) scheme.onSurface else androidx.compose.ui.graphics.Color.Transparent),
                        )
                    }
                }
                val now = model.nowAtMs
                if (now != null && total > 0) {
                    BoxWithConstraints(Modifier.fillMaxWidth()) {
                        val offset = maxWidth * ((now - model.dayStartMs) / total).toFloat().coerceIn(0f, 1f)
                        Box(Modifier.offset(x = offset - 1.dp).size(2.dp, 26.dp).background(scheme.primary))
                    }
                }
            }
            Axis(model, text)
        }
        if (model.projectionStartsAtMs != null) {
            Text(text.sourceTitle(RecordsDaySource.AFTER_NOW), style = MaterialTheme.typography.bodySmall, color = scheme.outline)
        }
    }
}

/**
 * Midnight, six, noon, six, midnight in the records zone, placed against the
 * day's real length, so a 23-hour day is not stretched back to 24.
 */
@Composable
private fun Axis(model: RecordsDayCanvasModel, text: RecordsText) {
    val total = model.dayEndMs - model.dayStartMs
    val day = LocalDate.parse(model.dayKey)
    BoxWithConstraints(Modifier.fillMaxWidth().height(16.dp).clearAndSetSemantics {}) {
        val width = maxWidth
        listOf(0, 6, 12, 18, 24).forEach { hour ->
            val moment = if (hour == 24) model.dayEndMs else day.atTime(LocalTime.of(hour, 0)).atZone(text.zone).toInstant().toEpochMilli().toDouble()
            val fraction = if (total > 0) ((moment - model.dayStartMs) / total).coerceIn(0.0, 1.0) else 0.0
            val label = text.time(moment)
            val align = when (hour) {
                0 -> Alignment.CenterStart
                24 -> Alignment.CenterEnd
                else -> Alignment.Center
            }
            Box(Modifier.fillMaxWidth(), contentAlignment = align) {
                Text(
                    label,
                    Modifier.then(if (hour in 1..23) Modifier.offset(x = width * (fraction.toFloat() - 0.5f)) else Modifier),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun Conclusion(model: RecordsDayCanvasModel, text: RecordsText) {
    val scheme = MaterialTheme.colorScheme
    RecordsCard {
        Column(Modifier.padding(16.dp).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(text.string(R.string.recordsFreeAwake), style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(text.duration(model.wakingFreeMs.toDouble()), style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.SemiBold, maxLines = 1)
                Text(
                    text.percent(model.wakingFreeShare * 100),
                    Modifier.padding(bottom = 4.dp).semantics { contentDescription = "${text.string(R.string.recordsShareOfDay)} ${text.percent(model.wakingFreeShare * 100)}" },
                    style = MaterialTheme.typography.bodyLarge,
                    color = scheme.onSurfaceVariant,
                )
            }
            Text(text.string(R.string.recordsFreeAwakeFootnote), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
        }
    }
}

/** The full text account, also the band's alternative (iOS `RecordsDayIntervalRow`). */
@Composable
private fun Segments(model: RecordsDayCanvasModel, text: RecordsText) {
    val scheme = MaterialTheme.colorScheme
    RecordsCard {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(text.string(R.string.recordsDaySegments), style = MaterialTheme.typography.labelLarge, color = scheme.onSurfaceVariant)
            model.intervals.forEach { interval ->
                Row(
                    Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = spoken(interval, text, model.sleepFromHealth) },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Box(
                        Modifier.size(9.dp).clip(CircleShape).background(kindColor(interval.kind))
                            .estimatedHatch(interval.source.isEstimated, androidx.compose.ui.graphics.Color.White, spacing = 3.dp, lineWidth = 0.8.dp),
                    )
                    Column(Modifier.weight(1f)) {
                        Text(text.timeRange(interval.startAtMs, interval.endAtMs), style = MaterialTheme.typography.bodyMedium)
                        // A row names its source only when it differs from the whole day's.
                        if (interval.source != model.source || interval.unexplained) {
                            Text(sourceWords(interval, text, model.sleepFromHealth), style = MaterialTheme.typography.bodySmall, color = scheme.onSurfaceVariant)
                        }
                    }
                    Spacer(Modifier.width(8.dp))
                    Column(horizontalAlignment = Alignment.End) {
                        Text(text.kindTitle(interval.kind), style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant, maxLines = 1)
                        Text(text.duration(interval.durationMs.toDouble()), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}

/** What the timer noticed on this day, as it noticed it. */
@Composable
private fun Observations(context: RecordsContext, dayKey: String) {
    val text = context.text
    val items = context.queries.observationIndex[dayKey].orEmpty()
    val scheme = MaterialTheme.colorScheme
    RecordsCard {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(text.string(R.string.recordsObservations), style = MaterialTheme.typography.labelLarge, color = scheme.onSurfaceVariant)
            if (items.isEmpty()) {
                Text(text.string(R.string.recordsNoObservations), style = MaterialTheme.typography.bodyMedium, color = scheme.onSurfaceVariant)
            }
            items.forEach { item ->
                val kind = text.string(
                    when (item.kind) {
                        WorkObservationKind.TIMER_SURFACE_FIRST_SEEN -> R.string.recordsObservedFirstSeen
                        WorkObservationKind.COUNTDOWN_STARTED -> R.string.recordsObservedStarted
                        WorkObservationKind.COUNTDOWN_STOPPED -> R.string.recordsObservedStopped
                        WorkObservationKind.OVERTIME_DECLARED -> R.string.recordsObservedOvertime
                    },
                )
                Text("${text.time(item.occurredAtMs)} · $kind", style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}
